# -*- coding: utf-8; -*-
# Authors::   Kiyoshi Ikehara <kiyoshi.ikehara@gree.net>
# Copyright:: Copyright (C) GREE, Inc. 2011.
# License::   MIT-style

require 'flare/tools/node'
require 'flare/tools/index_server'
require 'flare/tools/common'
require 'flare/util/conversion'
require 'flare/util/constant'
require 'flare/util/bwlimit'
require 'flare/tools/cli/sub_command'
require 'flare/tools/cli/index_server_config'
require 'csv'
require 'tokyocabinet'


module Flare
  module Tools
    module Cli

      class Restore < SubCommand

        class Restorer
          attr_reader :name
          def iterate &block
            raise "internal error"
          end
          def close
            raise "internal error"
          end
        end

        class TchRestorer < Restorer
          # uint32_t flag -> L    // uint32_t
          # time_t   expire -> Q  // unsigned long
          # uint64_t size -> Q    // uint64_t
          # uint64_t version -> Q // uint64_t
          # uint32_t option -> L  // uint32_t
          def self.myname
            "tch"
          end
          def initialize filepath
            raise "input file not specified." if filepath.nil?
            raise "#{filepath} isn't a path." unless filepath.kind_of?(String)
            @hdb = TokyoCabinet::HDB.new
            @hdb.open(filepath, TokyoCabinet::HDB::OCREAT|TokyoCabinet::HDB::OREADER)
          end
          def iterate &block
            @hdb.iterinit
            while (key = @hdb.iternext)
              value = @hdb.get(key)
              a = value.unpack("LQQQC*")
              flag, expire, size, version = a.shift(4)
              data = a.pack("C*")
              block.call(key, data, flag, expire)
            end
          end
          def close
            @hdb.close
          end
        end

        Restorers = []
        Restorers << TchRestorer if defined? TokyoCabinet
        Formats = Restorers.map {|n| n.myname}

        include Flare::Util::Conversion
        include Flare::Util::Constant
        include Flare::Tools::Common
        include Flare::Tools::Cli::IndexServerConfig

        myname :restore
        desc   "restore data to nodes. (experimental)"
        usage  "restore [hostname:port]"

        def setup
          super
          set_option_index_server
          set_option_dry_run
          @optp.on('--input=FILE',             "input from file") {|v| @input = v}
          @optp.on('-f', '--format=FORMAT',          "input format [#{Formats.join(',')}]") {|v|
            @format = v
          }
          @optp.on('--bwlimit=BANDWIDTH',            "bandwidth limit (bps)") {|v| @bwlimit = v}
          @optp.on('--include=PATTERN',              "include pattern") {|v|
            begin
              @include = Regexp.new(v)
            rescue RegexpError => e
              raise "#{v} isn't a valid regular expression."
            end
          }
          @optp.on('--prefix-include=STRING',        "prefix string") {|v|
            @prefix_include = Regexp.new("^"+Regexp.escape(v))
          }
          @optp.on('--exclude=PATTERN',              "exclude pattern") {|v|
            begin
              @exclude = Regexp.new(v)
            rescue RegexpError => e
              raise "#{v} isn't a valid regular expression."
            end
          }
          @optp.on('--print-keys',                     "enables key dump to console") {@print_key = true}
        end

        def initialize
          super
          @input = nil
          @format = 'tch'
          @wait = 0
          @part = 0
          @partsize = 1
          @bwlimit = 0
          @include = nil
          @prefix_include = nil
          @exclude = nil
          @print_key = false
        end

        def execute(config, args)
          parse_index_server(config, args)
          STDERR.puts "please install tokyocabinet via gem command." unless defined? TokyoCabinet

          cluster = nil
          Flare::Tools::IndexServer.open(config[:index_server_hostname], config[:index_server_port], @timeout) do |s|
            cluster = Flare::Tools::Cluster.new(s.host, s.port, s.stats_nodes)
          end
          return S_NG if cluster.nil?

          partition_size = cluster.partition_size

          args = cluster.master_nodekeys

          unless @format.nil? || Formats.include?(@format)
            STDERR.puts "unknown format: #{@format}"
            return S_NG
          end

          if @prefix_include
            if @include
              STDERR.puts "--include option is specified."
              return S_NG
            end
            @include = @prefix_include
          end

          hosts = args.map {|x| x.split(':')}
          hosts.each do |x|
            if x.size == 2
              x << cluster.partition_of_nodename("#{x[0]}:#{x[1]}")
            elsif x.size == 4
              if x[3] =~ /^\d+$/
                STDERR.puts "invalid partition number '#{x.join(':')}'."
                x[3] = x[3].to_i
              else
                STDERR.puts "invalid partition number '#{x.join(':')}'."
                return S_NG
              end
            else
              STDERR.puts "invalid argument '#{x.join(':')}'."
              return S_NG
            end
          end

          restorer = case @format
                     when TchRestorer.myname
                       TchRestorer.new(@input)
                     else
                       raise "invalid format"
                     end

          nodes = hosts.map do |hostname,port|
            Flare::Tools::Node.open(hostname, port.to_i, @timeout, @bwlimit, @bwlimit)
          end

          count = 0
          restorer.iterate do |key,data,flag,expire|
            if @include.nil? || @include =~ key
              next if @exclude && @exclude =~ key
              STDOUT.puts key if @print_key
              nodes[0].set(key, data, flag, expire) unless @dry_run
              count += 1
            end
          end
          STDERR.puts "#{count} entries have been restored."

          nodes.each do |n|
            n.close
          end

          restorer.close

          S_OK
        end # execute()

      end
    end
  end
end


