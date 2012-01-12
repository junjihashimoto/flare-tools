# -*- coding: utf-8; -*-
# Authors::   Kiyoshi Ikehara <kiyoshi.ikehara@gree.co.jp>
# Copyright:: Copyright (C) Gree,Inc. 2011. All Rights Reserved.
# License::   NOTYET

require 'flare/tools/stats'
require 'flare/tools/node'
require 'flare/tools/index_server'
require 'flare/tools/common'
require 'flare/util/conversion'
require 'flare/util/constant'
require 'flare/tools/cli/sub_command'

require 'csv'

module Flare
  module Tools
    module Cli
      
      class Dumpkey < SubCommand
        include Flare::Util::Conversion
        include Flare::Util::Constant
        include Flare::Tools::Common
        
        myname :dumpkey
        desc   "dump key from nodes."
        usage  "dumpkey [hostname:port] ..."
        
        def setup(opt)
          opt.on('-o', '--output=[FILE]',            "outputs to file") {|v| @output = v}
          opt.on('-f', '--format=[FORMAT]',          "output format [csv]") {|v| @format = v}
          opt.on('-p', '--partition=[NUMBER]',       "partition number") {|v| @part = v.to_i if v.to_i >= 0}
          opt.on('-s', '--partition-size=[SIZE]',    "partition size") {|v| @partsize = v.to_i if v.to_i > 0}
          opt.on(      '--bwlimit=[BANDWIDTH]',      "bandwidth limit (bytes/s)") {|v| @bwlimit = v.to_i if v.to_i > 0}
        end

        def initialize
          super
          @output = nil
          @format = nil
          @part = nil
          @partsize = nil
          @bwlimit = nil
        end

        def execute(config, *args)
          return S_NG if args.size < 1

          unless @format.nil?
            unless ["csv"].include? @format
              puts "unknown format: #{@format}"
              return S_NG
            end
          end

          hosts = args.map {|x| x.split(':')}
          hosts.each do |x|
            if x.size != 2
              puts "invalid argument '#{x.join(':')}'."
              return S_NG
            end
          end
          
          hosts.each do |hostname,port|
            Flare::Tools::Node.open(hostname, port.to_i, config[:timeout]) do |n|
              output = STDOUT
              unless @output.nil?
                output = File.open(@output, "w")
              end
              if @format == "csv"
                writer = CSV::Writer.generate(output)
                output.puts "# key"
              end
              basetime = Time.now
              n.dumpkey(@part, @partsize) do |key|
                if @format == "csv"
                  writer << [key]
                else
                  output.puts "#{key}"
                end
                unless @bwlimit.nil?
                  while n.received_size > (Time.now-basetime)*@bwlimit
                    sleep 0.001
                  end
                  if Time.now-basetime > 1.0
                    n.received_size = 0
                    basetime = Time.now
                  end
                end
                false
              end
              output.close if output != STDOUT
            end
          end
          
          S_OK
        end # execute()
        
        def stat_one_node(s)
          
        end

      end
    end
  end
end

