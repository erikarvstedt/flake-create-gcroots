#!/usr/bin/env ruby
require 'etc'
require 'fileutils'
require 'json'
require 'open3'
require 'sqlite3'

FetcherCacheDB = File.expand_path('~/.cache/nix/fetcher-cache-v2.sqlite')
ZipBallInputTypes = %w(github gitlab sourcehut)

Input = Struct.new(:name, :lock, :is_zipball, :store_path)
Inputs = Struct.new(:store_path_inputs, :zipball_inputs)

def exit_with_err(msg)
  warn(msg)
  exit(1)
end

def get_inputs(lockfile)
  locks = JSON.load(File.read(lockfile))
  inputs = Inputs.new([], [])
  locks['nodes'].each do |name, node|
    if !node.fetch("flake", true)
      warn "Warning: Skipping non-flake input `#{name}`. (These can't be fetched with `builtins.getFlake`.)"
      next
    end
    locked = node["locked"]
    if locked
      input = Input.new(name, locked)
      if ZipBallInputTypes.include? locked.fetch('type')
        input.is_zipball = true
        inputs.zipball_inputs << input
      else
        input.is_zipball = false
        inputs.store_path_inputs << input
      end
    end
  end
  inputs
end

# Reconstruct a flake URL from a flake input attrset
def make_flake_url(lock)
  type = lock.fetch('type')
  if lock.key?('url') && lock.key?('rev')
    "#{type}+#{lock['url']}?rev=#{lock['rev']}"
  elsif ZipBallInputTypes.include? type
    "#{type}:#{lock.fetch('owner')}/#{lock.fetch('repo')}/#{lock.fetch('rev')}"
  else
    exit_with_err("Don't know how to create flake URL from:\n#{lock.pretty_inspect}")
  end
end

def get_flake_expr(lock)
  %(builtins.getFlake "#{make_flake_url(lock)}")
end

def eval_inputs(inputs)
  input_attrs = [
    *(inputs.store_path_inputs.map { |input| %(#{input.name} = "${#{get_flake_expr(input.lock)}}";) }),
    # Use toString to only fetch the zipball without extracting it
    *(inputs.zipball_inputs.map { |input| %(#{input.name} = toString (#{get_flake_expr(input.lock)});) })
  ]

  nix_expr = <<~EOF
  {
  #{input_attrs.map { |expr| expr.prepend('  ') }.join("\n")}
  }
  EOF

  stdout, status = Open3.capture2('nix', 'eval', '--impure', '--json', '--expr', nix_expr)
  if !status.success?
    warn "\n"
    warn "Error occured while evaluating expression:\n#{nix_expr}"
    exit status.exitstatus
  end

  JSON.load(stdout)
end

def get_zipball_store_paths(inputs)
  db = SQLite3::Database.new(FetcherCacheDB, readonly: true)
  get_path = db.prepare("select path from Cache where input like ? limit 1")

  inputs.each do |input|
    rev = input.lock.fetch('rev')
    result = get_path.execute("%#{rev}%zipball%").to_a
    if result.empty?
      exit_with_err("Couldn't find store path for zipball input:\n#{input.lock.pretty_inspect}")
    end
    input.store_path = result.first.first
  end
end

# Sets `store_path` for each input
def get_store_paths(inputs)
  evaled_inputs = eval_inputs(inputs)
  get_zipball_store_paths(inputs.zipball_inputs)
  inputs.store_path_inputs.each { |input| input.store_path = evaled_inputs.fetch(input.name) }
end

def add_gcroots(lockfile, inputs)
  flake_path = File.dirname(File.expand_path(lockfile))
  dir = "/nix/var/nix/gcroots/per-user/#{Etc.getlogin}/flake-inputs#{flake_path}"
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(dir)
  inputs.each { |input| FileUtils.ln_s(input.store_path, File.join(dir, input.name)) }
  dir
end

def run(lockfile)
  inputs = get_inputs(lockfile)
  get_store_paths(inputs)
  # pp inputs

  all_inputs = inputs.store_path_inputs + inputs.zipball_inputs
  gcroots_dir = add_gcroots(lockfile, all_inputs)

  puts "Created #{all_inputs.size} links in #{gcroots_dir}:"
  longest_name = all_inputs.map { |input| input.name.length }.max
  puts all_inputs.map { |input|
    [
      "#{input.name}:".ljust(longest_name + 2),
      input.store_path,
      *(" (zipball)" if input.is_zipball)
    ].join
  }
end

def app(lockfile = nil)
  if !lockfile
    if File.exists?('flake.lock')
      lockfile = 'flake.lock'
    else
      exit_with_err("No lockfile provided via cmdline args and no 'flake.lock' in working directory.")
    end
  end
  lockfile = File.expand_path(lockfile)
  run(lockfile)
end

if __FILE__ == $0
  app(ARGV[0])
end
