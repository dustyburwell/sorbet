# frozen_string_literal: true
# typed: true

require_relative './lazy_enum_accessors'

require_yjit = ARGV.include?('--require-yjit')
if require_yjit && !(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?)
  raise 'YJIT must be enabled'
end

# Warm the caller and generated accessors before exercising deferred instances.
ordinary = LazyAccessorDocument.new(value: LazyAccessorEnum::Known)
1_000.times do
  LazyAccessorCaller.read(ordinary)
  LazyAccessorCaller.write(ordinary, LazyAccessorEnum::Known)
  LazyAccessorCaller.read_optional(ordinary)
  LazyAccessorCaller.write_optional(ordinary, nil)
  LazyAccessorCaller.read_ordinary(ordinary)
end

1_000.times do
  known = LazyAccessorDocument.from_hash('value' => 'known', 'optional' => 'known').freeze
  raise 'incorrect frozen read' unless LazyAccessorCaller.read(known).equal?(LazyAccessorEnum::Known)
  raise 'incorrect repeated read' unless LazyAccessorCaller.read(known).equal?(LazyAccessorEnum::Known)
  raise 'incorrect nilable read' unless LazyAccessorCaller.read_optional(known).equal?(LazyAccessorEnum::Known)
  raise 'incorrect dynamic read' unless known.class.decorator.prop_get(known, :value).equal?(LazyAccessorEnum::Known)

  unknown = LazyAccessorDocument.from_hash('value' => 'unknown', 'optional' => 'unknown')
  raise 'incorrect ordinary read' unless LazyAccessorCaller.read_ordinary(unknown) == 'ordinary'
  raise 'lost pending value' unless unknown.serialize.fetch('value') == 'unknown'
  begin
    LazyAccessorCaller.read(unknown)
    raise 'expected strict enum read'
  rescue KeyError => e
    raise unless e.message.include?('LazyAccessorDocument#value')
  end

  copy = unknown.dup
  LazyAccessorCaller.write(copy, LazyAccessorEnum::Known)
  raise 'stale pending value' unless LazyAccessorCaller.read(copy).equal?(LazyAccessorEnum::Known)
  raise 'incorrect replacement serialization' unless copy.serialize.fetch('value') == 'known'
  raise 'modified original' unless unknown.serialize.fetch('value') == 'unknown'
  LazyAccessorCaller.write_optional(copy, nil)
  raise 'stale nilable value' unless LazyAccessorCaller.read_optional(copy).nil?
  raise 'serialized replaced nil' if copy.serialize.key?('optional')
end

# Installing a guard after warmup must invalidate any optimized dispatch.
guarded = LazyAccessorDocument.from_hash('value' => 'unknown')
guarded.singleton_class.prepend(LazyAccessorGuard)
begin
  LazyAccessorCaller.read(guarded)
  raise 'expected guard'
rescue RuntimeError => e
  raise unless e.message == 'restricted'
end

if require_yjit
  stats = RubyVM::YJIT.runtime_stats
  raise 'no JIT compilation occurred' unless stats && stats.fetch(:compiled_iseq_count) > 0
  if RubyVM::YJIT.respond_to?(:insns_compiled)
    methods = %i[read write read_optional write_optional read_ordinary].map do |name|
      T::Utils.signature_for_method(LazyAccessorCaller.method(name)).method
    end
    methods << LazyAccessorDocument.instance_method(:value)
    methods << LazyAccessorDocument.instance_method(:value=)
    methods.each do |method|
      raise "accessor path not compiled: #{method}" if T.unsafe(RubyVM::YJIT).insns_compiled(method).empty?
    end
  end
end

puts 'PASS'
