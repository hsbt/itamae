require 'specinfra'
require 'singleton'

module Itamae
  class Backend
    UnknownBackendTypeError = Class.new(StandardError)
    CommandExecutionError = Class.new(StandardError)

    include Singleton

    def set_type(type, options = {})
      case type
      when :local
        Specinfra.configuration.backend = :exec
      when :ssh
        Specinfra.configuration.request_pty = true
        Specinfra.configuration.host = options.delete(:host)
        Specinfra.configuration.ssh_options = options

        Specinfra.configuration.backend = :ssh
      else
        raise UnknownBackendTypeError, "'#{type}' backend is unknown."
      end
    end

    def run_command(commands, options = {})
      options = {error: true}.merge(options)

      if commands.is_a?(Array)
        command = commands.map do |cmd|
          Shellwords.escape(cmd)
        end.join(' ')
      else
        command = commands
      end

      result = Specinfra::Runner.run_command(command)
      exit_status = result.exit_status

      if exit_status == 0 || !options[:error]
        method = :debug
        message = "  Command `#{command}` exited with #{exit_status}"
      else
        method = :error
        message = "  Command `#{command}` failed. (exit status: #{exit_status})"
      end

      Logger.public_send(method, message)

      {"stdout" => result.stdout, "stderr" => result.stderr}.each_pair do |name, value|
        if value && value != ''
          value.each_line do |line|
            # remove control chars
            case line.encoding
            when Encoding::UTF_8
              line = line.tr("\u0000-\u001f\u007f\u2028",'')
            end

            Logger.public_send(method, "    #{name} | #{line}")
          end
        end
      end

      if options[:error] && exit_status != 0
        raise CommandExecutionError
      end

      result
    end

    def run_specinfra(type, *args)
      command = Specinfra.command.get(type, *args)

      if type.to_s.start_with?("check_")
        result = run_command(command, error: false)
        result.exit_status == 0
      else
        run_command(command)
      end
    end

    def send_file(*args)
      Specinfra::Runner.send_file(*args)
    end
  end
end
