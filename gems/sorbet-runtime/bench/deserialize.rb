# frozen_string_literal: true
# typed: true

require 'benchmark'

require_relative '../lib/sorbet-runtime'

module SorbetBenchmarks
  module Deserialize

    class Example
      include T::Props::Serializable

      class Subdoc
        include T::Props::Serializable
        prop :prop, String
      end

      prop :prop1, T.nilable(Integer)
      prop :prop2, Integer, default: 0
      prop :prop3, Integer
      prop :prop4, T::Array[Integer]
      prop :prop5, T::Array[Integer], default: []
      prop :prop6, T::Hash[String, Integer]
      prop :prop7, T::Hash[String, Integer], default: {}
      prop :prop8, T.nilable(Subdoc)
      prop :prop9, T::Array[Subdoc], default: []
      prop :prop10, T::Hash[String, Subdoc], default: {}
    end

    class ExampleEnum < T::Enum
      enums do
        One = new('one')
      end
    end

    module DeferredEnums
      include T::Props::Plugin
      module DecoratorMethods
        attr_accessor :defer_enums

        def supports_lazy_enum_deserialization?
          true
        end

        def lazy_enum_deserialization?(instance)
          !!defer_enums
        end
      end
    end

    class EnumChild < T::Struct
      include DeferredEnums
      prop :first, ExampleEnum
      prop :second, T.nilable(ExampleEnum)
      prop :third, ExampleEnum
    end

    class EnumParent < T::Struct
      prop :children, T::Array[EnumChild]
    end

    def self.measure_enum_case(label, iterations, &block)
      1_000.times(&block)
      GC.start
      before = GC.stat(:total_allocated_objects)
      result = Benchmark.measure { iterations.times(&block) }
      allocations = GC.stat(:total_allocated_objects) - before
      puts "#{label}: #{(result.real * 1_000_000 / iterations).round(3)} μs/iter, #{(allocations.to_f / iterations).round(3)} allocations/iter"
    end

    def self.enum_properties(iterations=100_000)
      child = {'first' => 'one', 'second' => 'one', 'third' => 'one'}
      nested = {'children' => [child, child, child]}
      no_enum = {'prop3' => 0, 'prop4' => [], 'prop6' => {}}
      [false, true].each do |defer|
        EnumChild.decorator.defer_enums = defer
        label = defer ? 'deferred enums' : 'eager enums'
        measure_enum_case("#{label}, no-enum load", iterations) { Example.from_hash(no_enum) }
        measure_enum_case("#{label}, nested load", iterations) { EnumParent.from_hash(nested) }
        measure_enum_case("#{label}, load + first read", iterations) { EnumChild.from_hash(child).first }
        resolved = EnumChild.from_hash(child)
        resolved.first
        measure_enum_case("#{label}, repeated read", iterations) { resolved.first }
        unread = EnumParent.from_hash(nested)
        measure_enum_case("#{label}, unread serialize", iterations) { unread.serialize }
      end
    end

    def self.run
      input = {
        'prop3' => 0,
        'prop4' => [],
        'prop6' => {},
      }

      100_000.times do
        Example.from_hash(input)
      end

      result = Benchmark.measure do
        1_000_000.times do
          Example.from_hash(input)
        end
      end

      puts "T::Props.from_hash, mostly nil input (μs/iter):"
      puts result

      input = {
        'prop1' => 0,
        'prop2' => 0,
        'prop3' => 0,
        'prop4' => [1, 2, 3],
        'prop5' => [1, 2, 3],
        'prop6' => {'foo' => 1, 'bar' => 2},
        'prop7' => {'foo' => 1, 'bar' => 2},
        'prop8' => {'prop' => ''},
        'prop9' => [{'prop' => ''}, {'prop' => ''}],
        'prop10' => {'foo' => {'prop' => ''}, 'bar' => {'prop' => ''}},
      }

      100_000.times do
        Example.from_hash(input)
      end

      result = Benchmark.measure do
        1_000_000.times do
          Example.from_hash(input)
        end
      end

      puts "T::Props.from_hash, all props set (μs/iter):"
      puts result

      enum_properties
    end
  end
end
