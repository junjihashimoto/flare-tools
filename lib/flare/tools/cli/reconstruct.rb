# -*- coding: utf-8; -*-
# Authors::   Kiyoshi Ikehara <kiyoshi.ikehara@gree.net>
# Copyright:: Copyright (C) GREE, Inc. 2011.
# License::   MIT-style

require 'flare/tools/stats'
require 'flare/tools/node'
require 'flare/tools/index_server'
require 'flare/tools/cluster'
require 'flare/tools/common'
require 'flare/util/conversion'
require 'flare/util/constant'
require 'flare/tools/cli/sub_command'
require 'flare/tools/cli/index_server_config'

module Flare
  module Tools
    module Cli
      class Reconstruct < SubCommand
        include Flare::Util::Conversion
        include Flare::Util::Constant
        include Flare::Tools::Common
        include Flare::Tools::Cli::IndexServerConfig

        myname :reconstruct
        desc "reconstruct the database of nodes by copying."
        usage "reconstruct [hostname:port] ..."

        def setup
          super
          set_option_index_server
          set_option_dry_run
          set_option_force
          @optp.on('--unsafe',         "reconstruct a node safely"              ) { @unsafe = true }
          @optp.on('--safe',           "[obsolete] now reconstruct a node safely by default") do
            # do nothing
          end
          @optp.on('--retry=COUNT',    "specify retry count (default:#{@retry})") {|v| @retry = v.to_i }
          @optp.on('--all',            "reconstruct all nodes"                  ) { @all = true }
        end

        def initialize
          super
          @force = false
          @unsafe = false
          @retry = 10
          @all = false
        end

        def execute(config, args)
          parse_index_server(config, args)

          if @all
            unless args.empty?
              puts "don't specify any nodes with --all option."
              return S_NG
            else
              Flare::Tools::IndexServer.open(config[:index_server_hostname], config[:index_server_port], @timeout) do |s|
                cluster = Flare::Tools::Cluster.new(s.host, s.port, s.stats_nodes)
                args = cluster.master_and_slave_nodekeys
              end
            end
          else
            return S_NG if args.size == 0
          end

          hosts = args.map {|x| x.to_s.split(':')}
          hosts.each do |x|
            if x.size != 2
              puts "invalid argument '#{x.join(':')}'. it must be hostname:port."
              return S_NG
            end
          end

          status = S_OK

          Flare::Tools::IndexServer.open(config[:index_server_hostname], config[:index_server_port], @timeout) do |s|
            puts string_of_nodelist(s.stats_nodes, hosts.map {|x| nodekey_of(x[0], x[1])})

            hosts.each do |hostname,port|
              nodekey = nodekey_of hostname, port
              cluster = Flare::Tools::Cluster.new(s.host, s.port, s.stats_nodes)

              unless node = cluster.node_stat(nodekey)
                puts "#{nodekey} is not found in this cluster."
                return S_NG
              end
              unless cluster.reconstructable? nodekey
                puts "#{nodekey} is not reconstructable."
                status = S_NG
                next
              end
              is_safe = cluster.safely_reconstructable? nodekey
              if !@unsafe && !is_safe
                puts "The partition needs one more slave to reconstruct #{nodekey} safely."
                status = S_NG
                next
              end

              exec = @force
              unless exec
                puts "you are trying to reconstruct #{nodekey} without redanduncy." unless is_safe
                input = nil
                while input.nil?
                  STDERR.print "reconstructing node (node=#{nodekey}, role=#{node['role']}) (y/n/a/q/h:help): "
                  input = interruptible do
                    gets.chomp.upcase
                  end
                  case input
                  when "A"
                    @force = true
                    exec = true
                  when "N"
                  when "Q"
                    return S_OK
                  when "Y"
                    exec = true
                  else
                    puts "y: execute, n: skip, a: execute all the left nodes, q: quit, h: help"
                    input = nil
                  end
                end
              end
              if exec && !@dry_run
                puts "turning down..."
                s.set_state(hostname, port, 'down')

                puts "waiting for node to be active again..."
                sleep 3

                Flare::Tools::Node.open(hostname, port, @timeout) do |n|
                  n.flush_all
                end

                nretry = 0
                resp = false
                while resp == false && nretry < @retry
                  resp = s.set_role(hostname, port, 'slave', 0, node['partition'])
                  if resp
                    puts "started constructing node..."
                  else
                    nretry += 1
                    puts "waiting #{nretry} sec..."
                    sleep nretry
                    puts "retrying..."
                  end
                end
                balance = node['balance']
                if resp
                  wait_for_slave_construction(s, nodekey, @timeout)
                  unless @force
                    print "changing node's balance (node=#{nodekey}, balance=0 -> #{balance}) (y/n): "
                    exec = interruptible {(gets.chomp.upcase == "Y")}
                  end
                  s.set_role(hostname, port, 'slave', node['balance'], node['partition']) if exec
                  puts "done."
                else
                  error "failed to change the state."
                  status = S_NG
                end
              end
              @force = false if interrupted?
            end

            puts string_of_nodelist(s.stats_nodes, hosts.map {|x| "#{x[0]}:#{x[1]}"})
          end # open

          status
        end # execute()

      end
    end
  end
end
