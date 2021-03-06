# -*- coding: utf-8; -*-
# Authors::   Kiyoshi Ikehara <kiyoshi.ikehara@gree.net>
# Copyright:: Copyright (C) GREE, Inc. 2011.
# License::   MIT-style

require 'rubygems'
require 'flare/tools/node'

# 
module Flare
  module Test

    # == Description
    #
    class Node
      def initialize(hostname_port, pid)
        @hostname_port = hostname_port
        @hostname, @port = hostname_port.split(':')
        @pid = pid
        @alive = true
      end

      def open(&block)
        return nil unless @alive
        node = Flare::Tools::Node.open(@hostname, @port)
        return node if block.nil?
        ret = nil
        begin
          ret = block.call(node)
        rescue => e
          node.close
          raise e
        end
        ret
      end

      def stop
        Process.kill :STOP, @pid
      end

      def cont
        Process.kill :CONT, @pid
      end

      def terminate
        puts "killing... #{@pid}"
        begin
          Timeout.timeout(10) do
            Process.kill :TERM, @pid
            Process.waitpid @pid
          end
        rescue TimeoutError => e
          Process.kill :KILL, @pid
          Process.waitpid @pid
        end
        @alive = false
      end

      attr_reader :hostname, :port, :hostname_port, :pid
    end
  end
end
