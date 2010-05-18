require 'extlib'

class PIDFileUtilities

  def initialize(pid=nil, clazz=nil, path=nil)
    @pid = (pid) ? pid : Process.pid
    @name = ".rubymas-#{((clazz) ? clazz : self.class.to_s).snake_case}"
    @path = (path) ? path : self.class.tmp_directory

    File.open(File.join(@path, @name), "w", 0600) { |fd| fd.write(@pid) }
  end

  # This takes either a pid or a filename
  def self.process_exists?(pid_or_name)
    if pid_or_name.is_a?(Fixnum) || !(Integer(pid_name) rescue nil).nil?
      proc_file = pid_or_name
    else
      pid_filename = File.join(tmp_directory, ".rubymas-#{(pid_or_name.to_s.snake_case)}")
      if File.exists?(pid_filename)
        proc_file = File.read(pid_filename)
        File.exists?(File.join('/proc', proc_file))
      else
        return false
      end
    end
  end

  def self.pid_from_name(name)
    pid_filename = File.join(tmp_directory, ".rubymas-#{(name.to_s.snake_case)}")
    if File.exists?(pid_filename)
      Integer(File.read(pid_filename)) rescue false
    else
      false
    end
  end

  # Create a pid file.
  def create
    File.open(File.join(@path, @name), "w", 0600) do |fd|
      fd.write(@pid)
    end
  end

  def remove
    if File.exists?(File.join(@path, @name))
      begin
        File.unlink(File.join(@path, @name))
        return true
      rescue
        return false
      end
    end
 end

  def pid
    if File.exists?(File.join(@path, @name))
      Integer(File.read(File.join(@path, @name)))
    else
      nil
    end
  end

  private
  def self.tmp_directory
    # TODO have a config option to change this. It should go in /var/run.
    Dir::tmpdir
  end
end
