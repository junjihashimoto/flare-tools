# -*- coding: utf-8; -*-
# Authors::   Kiyoshi Ikehara <kiyoshi.ikehara@gree.co.jp>
# Copyright:: Copyright (C) Gree,Inc. 2011. All Rights Reserved.
# License::   NOTYET

require 'timeout'
require 'flare/tools/client'

# 
module Flare
  module Tools

    # == Description
    # 
    class Stats < Client

      defcmd :stats_nodes, 'stats nodes' do |resp|
        result = {}
        resp.gsub(/STAT /, '').split("\r\n").each do |x|
          ip, port, stat = x.split(":", 3)
          key, val = stat.split(" ")
          result["#{ip}:#{port}"] = {} if result["#{ip}:#{port}"].nil?
          result["#{ip}:#{port}"]['port'] = port
          result["#{ip}:#{port}"][key] = val
        end
        result
      end

      defcmd :stats, 'stats' do |resp|
        result = {}
        resp.gsub(/STAT /, '').split("\r\n").each do |x|
          key, val = x.split(" ", 2)
          result[key] = val
        end
        result
      end

      def stats_threads_by_peer
        result = {}
        stats_threads.each do |thread_id, stat|
          k = stat['peer']
          result[k] = {} if result[k].nil?
          result[k]['thread_id'] = thread_id
          result[k].merge!(stat)
        end
        result
      end

      def stats_threads
        stats_threads_
      end

      defcmd :stats_threads_, 'stats threads' do |resp|
        threads = {}
        resp.gsub(/STAT /, '').split("\r\n").each do |x|
          thread_id, stat = x.split(":", 2)
          key, val = stat.split(" ")
          threads[thread_id] = {} unless threads.has_key?(thread_id)
          threads[thread_id][key] = val
        end
        threads
      end

      defcmd :ping, 'ping' do |resp|
        true if resp
      end

      defcmd :quit, 'quit' do |resp|
        true
      end

    end
  end
end
