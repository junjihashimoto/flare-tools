# -*- coding: utf-8; -*-
# Authors::   Kiyoshi Ikehara <kiyoshi.ikehara@gree.co.jp>
# Copyright:: Copyright (C) Gree,Inc. 2011. All Rights Reserved.
# License::   NOTYET

require 'flare/tools/stats'

# 
module Flare
  module Tools

    # == Description
    # 
    class IndexServer < Stats

      def set_role(host, port, role, balance, partition)
        set_role_(host, port, role, balance, partition)
      end

      defcmd :set_role_, 'node role %s %d %s %d %d\r\n' do |resp|
        resp
      end

      def set_state(host, port, state)
        set_state_(host, port, state)
      end
      
      defcmd :set_state_, 'node state %s %s %s\r\n' do |resp|
        resp
      end

      def node_remove(host, port)
        node_remove_(host, port)
      end

      defcmd :node_remove_, 'node remove %s %s\r\n' do |resp|
        resp
      end

      def meta()
        meta_()
      end

      defcmd :meta_, 'meta\r\n' do |resp|
        meta = {}
        resp.split('\n').each do |line|
          cols = line.chomp.split(" ")
          meta[cols[1]] = cols[2]
        end
        meta
      end

    end
  end
end
