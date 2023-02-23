# -*- coding:binary; frozen_string_literal: true -*-
# based on https://github.com/jpeg-js/jpeg-js

class ZIMG::JPEG::Huffman
  def initialize lengths, values
    @root = self.class.build_table(lengths, values)
  end

  # input: IO, supporting individual bits reading
  # output: byte
  def decode bit_io
    node = @root
    while (bit=bit_io.next)
      node = node[bit]
      return node if node.is_a?(Integer)
      raise "invalid huffman sequence" unless node.is_a?(Array)
    end
    nil
  end

  def decode_debug bit_io
    node = @root
    a = []
    while (bit=bit_io.next)
      a << bit
      node = node[bit]
      if node.is_a?(Integer)
        puts "[d] #{a} => #{node}"
        return node
      end
      unless node.is_a?(Array)
        puts "[d] #{a}"
        raise "invalid huffman sequence"
      end
    end
    nil
  end

  def self.build_table lengths, values
    k = 0; code = []; length = 16
    while (length > 0 && !lengths[length - 1])
      length -= 1
    end
    code.push({children: [], index: 0})
    p = code[0]
    length.times do |i|
      lengths[i].times do |j|
        p = code.pop()
        p[:children][p[:index]] = values[k]
        while (p[:index] > 0)
          raise 'Could not recreate Huffman Table' if code.length == 0
          p = code.pop()
        end
        p[:index] += 1
        code.push(p)
        while (code.length <= i)
          code.push(q = {children: [], index: 0})
          p[:children][p[:index]] = q[:children]
          p = q
        end
        k += 1
      end
      if (i + 1 < length)
        # p here points to last code
        code.push(q = {children: [], index: 0})
        p[:children][p[:index]] = q[:children]
        p = q
      end
    end
    code[0][:children]
  end
end
