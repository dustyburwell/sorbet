# frozen_string_literal: true
# typed: ignore
require_relative '../../test_helper'

class Opus::Types::Test::Props::SerializableTest < Critic::Unit::UnitTest
  def assert_prop_error(match, &blk)
    ex = assert_raises(ArgumentError) do
      Class.new do
        include T::Props::Serializable
        class_exec(&blk)
      end
    end
    assert_match(match, ex.message)
  end

  class MySerializable
    include T::Props::Serializable
    prop :name, T.nilable(String), raise_on_nil_write: true
    prop :foo, T.nilable(T::Hash[T.any(String, Symbol), Object])
  end

  module ExtraProperties
    include T::Props::Plugin
    module DecoratorMethods
      extend T::Sig

      sig { params(instance: T::Props::PrettyPrintable, pp: T.any(PrettyPrint, PP::SingleLine)).void }
      def pretty_print_extra(instance, pp)
        super(instance, pp)
        pp.breakable
        pp.text("extra=true")
      end
    end
  end

  class MySerializableWithCustomExtraProps
    include T::Props::Serializable
    include ExtraProperties
  end

  def a_serializable
    m = MySerializable.new
    m.name = "Bob"
    m.foo  = {
      'age' => 7,
      'color' => 'red',
    }
    m
  end

  class DefaultsStruct
    include T::Props::Serializable
    include T::Props::WeakConstructor

    prop :prop1, T.nilable(String), default: "this is prop 1"
    prop :prop2, T.nilable(Integer), factory: -> { raise "don't call me" }
    prop :trueprop, T::Boolean, default: true
    prop :falseprop, T::Boolean, default: false
    prop :factoryprop, T::Boolean, factory: -> { true }

    prop :untyped_prop1, T.untyped, default: nil
    const :untyped_const1, T.untyped, default: nil
  end

  class NilDefaultRequired < T::Struct
    const :integer_const_nil_default, Integer, default: nil
    prop :integer_prop_nil_default, Integer, default: nil
  end

  describe ':default and :factory' do
    it 'defaults do not override on from_hash' do
      m = DefaultsStruct.from_hash('prop1' => 'value',
                                   'prop2' => 17)
      assert_equal('value', m.prop1)
      assert_equal(17, m.prop2)
    end

    it 'defaults do not replace nil on from_hash' do
      m = DefaultsStruct.from_hash('prop1' => 'value')
      assert_nil(m.prop2)

      m = DefaultsStruct.from_hash('prop2' => 30)
      assert_nil(m.prop1)
    end

    it 'does not call factories on from_hash' do
      m = DefaultsStruct.from_hash({})
      assert_nil(m.prop2)
    end

    it 'does call default on required prop' do
      m = DefaultsStruct.from_hash({})
      assert(m.trueprop)
    end

    it 'does call factory on required prop' do
      m = DefaultsStruct.from_hash({})
      assert(m.factoryprop)
    end
  end

  it 'returns the right required props' do
    assert_equal(
      Set[:trueprop, :falseprop, :factoryprop],
      DefaultsStruct.decorator.required_props.to_set
    )

    assert_equal(
      Set[:integer_const_nil_default, :integer_prop_nil_default],
      NilDefaultRequired.decorator.required_props.to_set
    )
  end

  class DefaultArrayStruct
    include T::Props::Serializable
    include T::Props::WeakConstructor

    prop :arrayprop, T::Array[String], default: []
  end

  class DefaultHashStruct
    include T::Props::Serializable
    include T::Props::WeakConstructor

    prop :hashprop, T::Hash[String, String], default: {}
  end

  describe 'default: with literals' do
    it 'does not share structure for arrays' do
      a = DefaultArrayStruct.new
      b = DefaultArrayStruct.new

      refute_equal(a.arrayprop.object_id, b.arrayprop.object_id)
    end

    it 'does not share structure for hashes' do
      a = DefaultHashStruct.new
      b = DefaultHashStruct.new

      refute_equal(a.hashprop.object_id, b.hashprop.object_id)
    end
  end

  class ParentWithNoDefault < T::InexactStruct
    prop :prop, String
  end

  class ChildWithDefault < ParentWithNoDefault
    prop :prop, String, default: '', override: true
  end

  it 'uses default set on child in constructor' do
    assert_equal('', ChildWithDefault.new.prop)
  end

  it 'serializes' do
    m = a_serializable

    hash = m.serialize
    assert_kind_of(Hash, hash)
    assert_equal("Bob", hash['name'])
    assert_equal(7, hash['foo']['age'])
  end

  describe '.inspect' do
    it 'inspects' do
      obj = a_serializable
      str = obj.inspect
      assert_equal("<Opus::Types::Test::Props::SerializableTest::MySerializable foo=#{obj.foo} name=\"Bob\">", str)
    end

    it 'inspects with extra props' do
      obj = a_serializable
      obj = obj.class.from_hash(obj.serialize.merge('not_a_prop' => 'but_here_anyway'))
      str = obj.inspect
      assert_equal("<Opus::Types::Test::Props::SerializableTest::MySerializable foo=#{obj.foo} name=\"Bob\" @_extra_props=<not_a_prop=\"but_here_anyway\">>", str)
    end

    it 'inspects with custom extra props' do
      obj = MySerializableWithCustomExtraProps.new
      obj = obj.class.from_hash(obj.serialize.merge('not_a_prop' => 'but_here_anyway'))
      str = obj.inspect
      assert_equal('<Opus::Types::Test::Props::SerializableTest::MySerializableWithCustomExtraProps @_extra_props=<not_a_prop="but_here_anyway"> extra=true>', str)
    end

    it 'inspects frozen structs' do
      obj = a_serializable.freeze
      str = obj.inspect
      assert_equal("<Opus::Types::Test::Props::SerializableTest::MySerializable foo=#{obj.foo} name=\"Bob\">", str)
    end
  end

  describe '.pretty_inspect' do
    it 'excludes extra props' do
      orig_obj = a_serializable
      obj = orig_obj.class.from_hash(orig_obj.serialize.merge('not_a_prop' => 'but_here_anyway'))
      expected_result = <<~INSPECT
        <Opus::Types::Test::Props::SerializableTest::MySerializable
         foo=#{orig_obj.foo}
         name="Bob">
      INSPECT
      str = obj.pretty_inspect
      assert_equal(expected_result, str)
    end

    it 'inspects with custom extra props' do
      obj = MySerializableWithCustomExtraProps.new
      obj = obj.class.from_hash(obj.serialize.merge('not_a_prop' => 'but_here_anyway'))
      expected_result = <<~INSPECT
        <Opus::Types::Test::Props::SerializableTest::MySerializableWithCustomExtraProps
         extra=true>
      INSPECT
      str = obj.pretty_inspect
      assert_equal(expected_result, str)
    end
  end

  describe '.from_hash' do
    it 'round-trips' do
      m = a_serializable
      assert_equal(m.serialize, m.class.from_hash(m.serialize).serialize)
    end

    it 'round-trips extra props' do
      m = a_serializable
      input = m.serialize.merge('not_a_prop' => 'foo')
      assert_equal('foo', m.class.from_hash(input).serialize['not_a_prop'])
    end

    it 'does not call the constructor' do
      MySerializable.any_instance.expects(:new).never
      MySerializable.from_hash({})
    end
  end

  describe 'error message' do
    it 'raises NoMethodError for prop deserialize error' do
      e = assert_raises(NoMethodError) do
        MySerializable.from_hash({'foo' => "Won't respond like hash"})
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'transform_values'")
    end

    it 'includes relevant generated code on deserialize when we raise' do
      e = assert_raises(NoMethodError) do
        MySerializable.from_hash({'foo' => "Won't respond like hash"})
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'transform_values'")
      assert_includes(e.message, "foo")
      assert_includes(e.message, "val.transform_values {|v| T::Props::Utils.deep_clone(v)}")
    end

    it 'includes relevant generated code on serialize' do
      m = a_serializable
      m.instance_variable_set(:@foo, "Won't respond like hash")
      e = assert_raises(NoMethodError) do
        m.serialize
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'transform_values'")
      assert_includes(e.message, 'h["foo"] = @foo.transform_values {|v| T::Props::Utils.deep_clone(v)}')
    end

    it 'handles exceptions without a #backtrace_locations' do
      mock = Object.new
      def mock.transform_values(...)
        raise NoMethodError, "undefined method 'transform_values'", caller # rubocop:disable Style/RaiseArgs
      end

      m = a_serializable
      m.instance_variable_set(:@foo, mock)
      e = assert_raises(NoMethodError) do
        m.serialize
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'transform_values'")
      assert_includes(e.message, 'h["foo"] = @foo.transform_values {|v| T::Props::Utils.deep_clone(v)}')
    end
  end

  class HasUnstoredProp < T::Struct
    prop :stored, String
    prop :not_stored, String, dont_store: true
  end

  describe 'dont_store prop' do
    it 'is not stored' do
      m = HasUnstoredProp.new(stored: 'foo', not_stored: 'bar')
      assert_equal({'stored' => 'foo'}, m.serialize)
    end

    it 'does not prevent extra_props from round-tripping' do
      input = {'stored' => 'foo', 'not_a_prop' => 'bar'}
      result = HasUnstoredProp.from_hash(input).serialize
      assert_equal('bar', result['not_a_prop'])
    end

    it 'is allowed even on strict deserialize' do
      input = {'stored' => 'foo', 'not_stored' => 'bar'}
      refute_nil(HasUnstoredProp.from_hash!(input))
    end
  end

  describe 'hash props' do
    it 'does not share structure on serialize' do
      m = MySerializable.new
      m.name = 'hi'
      m.foo = {'hello' => {'world' => 1}}
      h = m.serialize
      refute_equal(m.foo.object_id, h['foo'].object_id, "`foo` is the same object")
      refute_equal(m.foo['hello'].object_id, h['foo']['hello'].object_id, "`foo.hello` is the same object")
    end

    it 'does not share structure on deserialize' do
      h = {
        'name' => 'hi',
        'foo' => {'hello' => {'world' => 1}},
      }
      m = MySerializable.from_hash(h)
      refute_equal(m.foo.object_id, h['foo'].object_id, "`foo` is the same object")
      refute_equal(m.foo['hello'].object_id, h['foo']['hello'].object_id, "`foo.hello` is the same object")
    end
  end

  describe "prop declaration" do
    it ':name must be a string' do
      assert_prop_error(/Invalid name in prop/) do
        prop :foo, String, name: :goats
      end
    end
  end

  class MyNilableSerializable
    include T::Props::Serializable
    prop :name, T.nilable(String)
    prop :address, T.nilable(String)
  end

  describe "nilable" do
    it 'can serialize nilables' do
      obj = MyNilableSerializable.new
      obj.name = 'Avi'
      assert_equal({'name' => 'Avi'}, obj.serialize)

      obj = MyNilableSerializable.new
      obj.name = nil
      assert_equal({}, obj.serialize)
    end

    it 'can serialize optionals' do
      obj = MyNilableSerializable.new
      obj.address = 'TEST'
      assert_equal({'address' => 'TEST'}, obj.serialize)

      obj = MyNilableSerializable.new
      obj.address = nil
      assert_equal({}, obj.serialize)
    end
  end

  class NilSingleFieldStruct < T::Struct
    prop :foo, T.nilable(Integer), raise_on_nil_write: true
  end

  class NilFieldStruct < T::Struct
    prop :foo, T.nilable(Integer), raise_on_nil_write: true
    prop :bar, T.nilable(String), raise_on_nil_write: true
  end

  class NilFieldWeakConstructor
    include T::Props::Serializable
    include T::Props::WeakConstructor
    prop :prop, T.nilable(String), raise_on_nil_write: true
  end

  class NilDefaultStruct < T::Struct
    prop :prop, T.nilable(String), raise_on_nil_write: true, default: nil
  end

  describe 'raise_on_nil_write' do
    it 'requires the value to be true' do
      assert_prop_error(/if specified must be `true`/) do
        prop :foo, T.nilable(String), raise_on_nil_write: false
      end

      assert_prop_error(/if specified must be `true`/) do
        prop :foo, T.nilable(String), raise_on_nil_write: 1
      end
    end

    it 'requires the prop type to be nilable' do
      assert_prop_error(/requires that the type of `foo` be `T.nilable\(\.\.\.\)` \(given: String\)/) do
        prop :foo, String, raise_on_nil_write: true
      end

      assert_prop_error(/requires that the type of `foo` be `T.nilable\(\.\.\.\)` \(given: NilClass\)/) do
        prop :foo, NilClass, raise_on_nil_write: true
      end
    end

    it 'allows underspecified prop types' do
      Class.new do
        include T::Props::Serializable
        prop :untyped, T.untyped, raise_on_nil_write: true
        prop :object, Object, raise_on_nil_write: true
        prop :basic_object, BasicObject, raise_on_nil_write: true
        prop :interface, Kernel, raise_on_nil_write: true
      end
    end

    it 'forbids nil in setter' do
      struct = NilFieldStruct.new(foo: 1, bar: 'something')
      ex = assert_raises(TypeError) do
        struct.foo = nil
      end
      assert_includes(ex.message, "Can't set Opus::Types::Test::Props::SerializableTest::NilFieldStruct.foo to nil (instance of NilClass) - need a Integer")
      ex = assert_raises(TypeError) do
        struct.bar = nil
      end
      assert_includes(ex.message, "Can't set Opus::Types::Test::Props::SerializableTest::NilFieldStruct.bar to nil (instance of NilClass) - need a String")
    end

    it 'forbids nil in constructor' do
      assert_raises(ArgumentError) do
        NilFieldStruct.new
      end
      assert_raises(TypeError) do
        NilFieldStruct.new(foo: nil, bar: nil)
      end
    end

    it 'throws exception on nil serialize' do
      foo = NilFieldStruct.allocate
      ex = assert_raises(TypeError) do
        foo.serialize
      end
      assert_includes(ex.message, 'Opus::Types::Test::Props::SerializableTest::NilFieldStruct.foo not set for non-optional prop')
    end

    it 'does not assert when strict=false' do
      foo = NilFieldStruct.allocate
      foo.serialize(false)
    end

    it 'records the non-presence of required properties on deserialize' do
      struct = NilSingleFieldStruct.from_hash({})
      assert_nil(struct.foo)
      missing_props = struct.instance_variable_get(:@_required_props_missing_from_deserialize)
      refute_nil(missing_props)
      refute(missing_props.empty?)
      assert_equal(1, missing_props.length)
      assert(missing_props.include?(:foo))
    end

    it 'round-trips when required properties are not provided to deserialize' do
      struct = NilSingleFieldStruct.from_hash({})
      assert_nil(struct.foo)

      h = nil
      _stdout, msg_string = capture_io do
        h = struct.serialize
      end

      assert_instance_of(Hash, h)
      assert(h.empty?)
      assert_includes(msg_string, "missing required property in serialize")
      assert_includes(msg_string, "prop=:foo")
      assert_includes(msg_string, "class=Opus::Types::Test::Props::SerializableTest::NilSingleFieldStruct")
    end

    describe 'with weak constructor' do
      it 'forbids nil in setter' do
        struct = NilFieldWeakConstructor.new(prop: 'something')
        assert_raises(TypeError) do
          struct.prop = nil
        end
      end

      it 'allows implicit but forbids explicit nil in constructor' do
        struct = NilFieldWeakConstructor.new
        assert_nil(struct.prop)
        assert_raises(TypeError) do
          NilFieldWeakConstructor.new(prop: nil)
        end
      end

      it 'throws exception on nil serialize' do
        struct = NilFieldWeakConstructor.new
        assert_raises(TypeError) do
          struct.serialize
        end
      end
    end

    describe 'when default is nil' do
      # Is this intended? It seems like the behavior you'd want with T::Props::WeakConstructor,
      # not T::Props::Constructor / T::Struct
      it 'allows nil in constructor' do
        struct = NilDefaultStruct.new
        assert_nil(struct.prop)
        struct = NilDefaultStruct.new(prop: nil)
        assert_nil(struct.prop)
      end

      # Is this intended? It doesn't seem like the default should affect the behavior
      # of the setter
      it 'allows nil in setter' do
        struct = NilDefaultStruct.new(prop: 'something')
        struct.prop = nil
        assert_nil(struct.prop)
      end

      it 'throws exception on nil serialize' do
        struct = NilDefaultStruct.new
        assert_raises(TypeError) do
          struct.serialize
        end
      end
    end
  end

  class WithModel1 < T::Struct
    prop :foo, String
    prop :bar, T.nilable(Integer)
  end

  class WithModel2 < T::Struct
    prop :f1, String
    prop :f2, T.nilable(WithModel1)
  end

  describe 'with function' do
    it 'with simple fields' do
      a = WithModel1.new(foo: 'foo')
      b = a.with(bar: 10)

      assert_equal('foo', a.foo)
      assert_nil(a.bar)
      assert_equal('foo', b.foo)
      assert_equal(10, b.bar)
    end

    it 'with invalid fields' do
      a = WithModel1.new(foo: 'foo')
      e = assert_raises(ArgumentError) do
        a.with(non_bar: 10)
      end
      assert_equal("Unexpected arguments: input(#{{non_bar: 10}}), unexpected(#{{'non_bar' => 10}})", e.to_s) # rubocop:disable Lint/LiteralInInterpolation

      a = WithModel1.from_hash({'foo' => 'foo', 'foo1' => 'foo1'})
      e = assert_raises(ArgumentError) do
        a.with(non_bar: 10)
      end
      assert_equal("Unexpected arguments: input(#{{non_bar: 10}}), unexpected(#{{'non_bar' => 10}})", e.to_s) # rubocop:disable Lint/LiteralInInterpolation
    end

    it 'with overwrite fields' do
      a = WithModel1.new(foo: 'foo', bar: 10)
      b = a.with(bar: 20)

      assert_equal('foo', a.foo)
      assert_equal(10, a.bar)
      assert_equal('foo', b.foo)
      assert_equal(20, b.bar)
    end

    it 'with nested fields' do
      a = WithModel2.new(f1: 'foo')
      b = a.with(f2: {foo: 'foo', bar: 10})

      assert_equal('foo', a.f1)
      assert_nil(a.f2)
      assert_equal('foo', b.f1)
      refute_nil(b.f2)
      assert_equal('foo', b.f2.foo)
      assert_equal(10, b.f2.bar)
    end
  end

  class BooleanStruct < T::Struct
    prop :prop, T::Boolean
    prop :nilable_prop, T.nilable(T::Boolean)
  end

  describe 'boolean props' do
    it 'are not cloned on serde' do
      T::Props::Utils.expects(:deep_clone).never

      s = BooleanStruct.new(prop: true)
      assert_equal(true, BooleanStruct.from_hash(s.serialize).prop)
    end
  end

  class HeterogenousUnionStruct < T::Struct
    prop :prop, T.any(String, MySerializable)
  end

  describe 'heterogenous union props' do
    it 'are cloned on serde' do
      T::Props::Utils.expects(:deep_clone).with('foo').at_least_once.returns('foo')

      s = HeterogenousUnionStruct.new(prop: 'foo')
      assert_equal('foo', HeterogenousUnionStruct.from_hash(s.serialize).prop)
    end
  end

  class MultipleStructUnionStruct < T::Struct
    prop :prop, T.any(MySerializable, MyNilableSerializable)
  end

  describe 'unions of two different serializables' do
    it 'are just cloned on serde' do
      obj = MyNilableSerializable.new
      T::Props::Utils.expects(:deep_clone).with(obj).at_least_once.returns(obj)

      s = MultipleStructUnionStruct.new(prop: obj)
      assert_equal(obj, MultipleStructUnionStruct.from_hash(s.serialize).prop)
    end
  end

  class StructWithTuples < T::Struct
    prop :unary_tuple, [Symbol]
    prop :tuple, [Integer, String]
    prop :triple, [Float, TrueClass, FalseClass]
    prop :array_of_tuple, T::Array[[Integer, String]]
    prop :tuple_with_combinator, [T.nilable(String)]
    prop :combinator_with_tuple, T.nilable([Symbol, Float])
  end

  describe 'tuples' do
    it 'typechecks' do
      exn = assert_raises(TypeError) do
        StructWithTuples.new(
          unary_tuple: ['not a symbol'],
          tuple: [0, ''],
          triple: [0.0, true, false],
          array_of_tuple: [[0, '']],
          tuple_with_combinator: [nil]
        )
      end
      assert_includes(exn.message, '.unary_tuple to ["not a symbol"] (instance of Array) - need a [Symbol]')
    end

    it 'roundtrips' do
      expected = StructWithTuples.new(
        unary_tuple: [:hello],
        tuple: [0, ''],
        triple: [0.0, true, false],
        array_of_tuple: [[0, '']],
        tuple_with_combinator: [nil]
      )

      actual = StructWithTuples.from_hash(expected.serialize)

      assert_equal(expected.unary_tuple, actual.unary_tuple)
      assert_equal(expected.tuple, actual.tuple)
      assert_equal(expected.triple, actual.triple)
      assert_equal(expected.array_of_tuple, actual.array_of_tuple)
      assert_equal(expected.tuple_with_combinator, actual.tuple_with_combinator)
      assert_nil(actual.combinator_with_tuple)
    end
  end

  class StructWithShapes < T::Struct
    prop :empty_shape, {}
    prop :symbol_key_shape, {foo: Integer}
    prop :string_key_shape, {'foo' => Integer}
  end

  describe 'shapes' do
    it 'typechecks' do
      exn = assert_raises(TypeError) do
        StructWithShapes.new(
          empty_shape: {},
          symbol_key_shape: {foo: 0},
          string_key_shape: {not_a_string: 0}
        )
      end
      assert_includes(exn.message, ".string_key_shape to #{{not_a_string: 0}} (instance of Hash) - need a {\"foo\" => Integer}") # rubocop:disable Lint/LiteralInInterpolation
    end

    it 'roundtrips' do
      expected = StructWithShapes.new(
        empty_shape: {},
        symbol_key_shape: {foo: 0},
        string_key_shape: {'foo' => 0}
      )

      actual = StructWithShapes.from_hash(expected.serialize)

      assert_equal(expected.empty_shape, actual.empty_shape)
      assert_equal(expected.symbol_key_shape, actual.symbol_key_shape)
      assert_equal(expected.string_key_shape, actual.string_key_shape)
    end
  end

  class CustomType
    extend T::Props::CustomType

    attr_accessor :value

    def self.deserialize(value)
      result = new
      result.value = value.clone.freeze
      result
    end

    def self.serialize(instance)
      instance.value
    end
  end

  class CustomTypeStruct < T::Struct
    prop :single, T.nilable(CustomType)
    prop :array, T::Array[CustomType], default: []
    prop :hash_key, T::Hash[CustomType, String], default: {}
    prop :hash_value, T::Hash[String, CustomType], default: {}
    prop :hash_both, T::Hash[CustomType, CustomType], default: {}
  end

  class CustomTypeWrapper
    include T::Props::Serializable
    prop :struct, CustomTypeStruct
  end

  describe 'custom type' do
    it 'round trips as plain value' do
      assert_equal('foo', CustomTypeStruct.from_hash({'single' => 'foo'}).serialize['single'])
    end

    it 'round trips with arrays' do
      a = %w[bar baz]
      assert_equal(a, CustomTypeStruct.from_hash({'array' => a}).serialize['array'])
    end

    it 'raises serialize errors when props with a custom subtype store the wrong datatype' do
      struct = CustomTypeStruct.new
      struct.instance_variable_set(:@single, 'not a serializable thing')
      e = assert_raises(TypeError) do
        struct.serialize
      end

      assert_includes(e.message, "Expected type T::Props::CustomType")
    end

    # It's hard to write tests for a CustomType with a custom deserialize method, so skip that.

    it 'raises serialize errors when props with a serializable subtype store the wrong datatype' do
      struct = CustomTypeWrapper.new
      struct.instance_variable_set(:@struct, 'not a serializable thing')
      e = assert_raises(NoMethodError) do
        struct.serialize
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'serialize'")
    end

    it 'raises deserialize errors when props with a serializable subtype store the wrong datatype' do
      obj = 'not a serializable thing'
      e = assert_raises(TypeError) do
        CustomTypeWrapper.from_hash({'struct' => obj})
      end

      assert_includes(e.message, 'provided to from_hash')
    end

    it 'round trips as array value' do
      assert_equal(['foo'], CustomTypeStruct.from_hash({'array' => ['foo']}).serialize['array'])
    end

    it 'raises serialize errors when props with an array of a custom subtype store the wrong datatype' do
      obj = CustomType.new
      struct = CustomTypeStruct.new
      struct.instance_variable_set(:@array, obj)
      e = assert_raises(NoMethodError) do
        struct.serialize
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'map'")
    end

    it 'raises deserialize errors when props with an array of a custom subtype store the wrong datatype' do
      e = assert_raises(NoMethodError) do
        CustomTypeStruct.from_hash({'array' => CustomType.new})
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'map'")
    end

    it 'round trips as hash key' do
      assert_equal({'foo' => 'bar'}, CustomTypeStruct.from_hash({'hash_key' => {'foo' => 'bar'}}).serialize['hash_key'])
    end

    it 'raises serialize errors when props with a hash with keys of a custom subtype store the wrong datatype' do
      obj = CustomType.new
      struct = CustomTypeStruct.new
      struct.instance_variable_set(:@hash_key, obj)
      e = assert_raises(NoMethodError) do
        struct.serialize
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'transform_keys'")
    end

    it 'raises deserialize errors when props with a hash with keys of a custom subtype store the wrong datatype' do
      e = assert_raises(NoMethodError) do
        CustomTypeStruct.from_hash({'hash_key' => 'not a hash'})
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'transform_keys'")
    end

    it 'round trips as hash value' do
      assert_equal({'foo' => 'bar'}, CustomTypeStruct.from_hash({'hash_value' => {'foo' => 'bar'}}).serialize['hash_value'])
    end

    it 'raises serialize errors when props with a hash with values of a custom subtype store the wrong datatype' do
      obj = CustomType.new
      struct = CustomTypeStruct.new
      struct.instance_variable_set(:@hash_value, obj)
      e = assert_raises(NoMethodError) do
        struct.serialize
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'transform_values'")
    end

    it 'raises deserialize errors when props with a hash with values of a custom subtype store the wrong datatype' do
      e = assert_raises(NoMethodError) do
        CustomTypeStruct.from_hash({'hash_value' => 'not a hash'})
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'transform_values'")
    end

    it 'round trips as hash key and value' do
      assert_equal({'foo' => 'bar'}, CustomTypeStruct.from_hash({'hash_both' => {'foo' => 'bar'}}).serialize['hash_both'])
    end

    it 'raises serialize errors when props with a hash with keys/values of a custom subtype store the wrong datatype' do
      obj = CustomType.new
      struct = CustomTypeStruct.new
      struct.instance_variable_set(:@hash_both, obj)
      e = assert_raises(NoMethodError) do
        struct.serialize
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'each_with_object'")
    end

    it 'raises deserialize errors when props with a hash with keys/values of a custom subtype store the wrong datatype' do
      e = assert_raises(NoMethodError) do
        CustomTypeStruct.from_hash({'hash_both' => 'not a hash'})
      end

      assert_includes(e.message.tr("`", "'"), "undefined method 'each_with_object'")
    end
  end

  class SetPropStruct
    include T::Props::Serializable
    prop :set, T::Set[String]
  end

  describe 'set props' do
    it 'round trips' do
      set = Set['foo']
      struct = SetPropStruct.new
      struct.set = set

      h = struct.serialize
      assert_equal(set, h['set'])

      roundtripped = SetPropStruct.from_hash(h)
      assert_equal(roundtripped.set, set)
    end

    it 'does not share structure on serialize' do
      set = Set['foo']
      struct = SetPropStruct.new
      struct.set = set
      h = struct.serialize
      refute_equal(struct.set.object_id, h['set'].object_id, "`set` is the same object")
    end

    it 'does not share structure on deserialize' do
      set = Set['foo']
      h = {
        'set' => set,
      }
      struct = SetPropStruct.from_hash(h)
      refute_equal(struct.set.object_id, h['set'].object_id, "`set` is the same object")
    end
  end

  class CustomSetPropStruct
    include T::Props::Serializable
    prop :set, T::Set[CustomType]
  end

  describe 'custom set props' do
    it 'round trips' do
      array = [3]
      obj = CustomType.new
      obj.value = array
      set = Set[obj]
      struct = CustomSetPropStruct.new
      struct.set = set
      h = struct.serialize
      assert_equal(1, h['set'].length)
      assert(h['set'].include?(array))

      roundtripped = CustomSetPropStruct.from_hash(h)
      assert_equal(1, roundtripped.set.length)
      value = roundtripped.set.to_a[0].value
      assert_equal(array, value)
    end

    it 'raises serialize errors' do
      not_a_set = 1234
      struct = CustomSetPropStruct.new
      struct.instance_variable_set(:@set, not_a_set)
      e = assert_raises(TypeError) do
        struct.serialize
      end

      assert_includes(e.message, "value must be enumerable")
    end

    it 'raises deserialize errors' do
      obj = CustomType.new
      e = assert_raises(TypeError) do
        CustomSetPropStruct.from_hash({'set' => obj})
      end

      assert_includes(e.message, "value must be enumerable")
    end
  end

  class MyEnum < T::Enum
    enums do
      FOO = new
      BAR = new
    end
  end

  class EnumStruct < T::Struct
    prop :enum, MyEnum
    prop :deprecated_enum_of_enums, T.nilable(T.deprecated_enum([MyEnum::BAR]))
  end

  class RedundantEnumStruct < T::Struct
    prop :deprecated_enum, T.all(MyEnum, T.deprecated_enum(MyEnum.values))
  end

  describe 'enum' do
    it 'round trips' do
      s = EnumStruct.new(enum: MyEnum::FOO, deprecated_enum_of_enums: MyEnum::BAR)

      serialized = s.serialize
      assert_equal('foo', serialized['enum'])
      assert_equal('bar', serialized['deprecated_enum_of_enums'])

      roundtripped = EnumStruct.from_hash(serialized)
      assert_equal(MyEnum::FOO, roundtripped.enum)
      assert_equal(MyEnum::BAR, roundtripped.deprecated_enum_of_enums)
    end

    it 'does not break during serde when used redundantly with legacy T.deprecated_enum' do
      s = RedundantEnumStruct.new(deprecated_enum: MyEnum::FOO)
      serialized = s.serialize
      assert_equal('foo', serialized['deprecated_enum'])

      roundtripped = RedundantEnumStruct.from_hash(serialized)
      assert_equal(MyEnum::FOO, roundtripped.deprecated_enum)
    end
  end

  class SuperStruct
    include T::Props::Serializable

    prop :superprop, T.nilable(String)
  end

  module Mixin
    include T::Props::Serializable
    prop :mixinprop, T.nilable(String)
  end

  # In the style of ActiveSupport::Concern
  module Concern
    def self.included(other)
      other.instance_exec do
        prop :concernprop, T.nilable(String)
      end
    end
  end

  class SubStruct < SuperStruct
    include Mixin
    include Concern
    prop :subprop, T.nilable(String)
  end

  describe 'with inheritance' do
    it 'round trips parent prop' do
      assert_equal('foo', SubStruct.from_hash('superprop' => 'foo').serialize['superprop'])
    end

    it 'round trips child prop' do
      assert_equal('foo', SubStruct.from_hash('subprop' => 'foo').serialize['subprop'])
    end

    it 'round trips prop from T::Props::Serializable mixin' do
      assert_equal('foo', SubStruct.from_hash('mixinprop' => 'foo').serialize['mixinprop'])
    end

    it 'round trips prop from mixin which uses def self.included' do
      assert_equal('foo', SubStruct.from_hash('concernprop' => 'foo').serialize['concernprop'])
    end
  end

  class ReopenedSuperStruct; end

  class ReopenedSuperStruct
    include T::Props::Serializable

    prop :superprop, T.nilable(String)
  end

  class ReopenedSubStruct < ReopenedSuperStruct
    include Mixin
    include Concern
  end

  class ReopenedSubStruct < ReopenedSuperStruct
    prop :subprop, T.nilable(String)
  end

  describe 'with reopening' do
    it 'round trips parent prop' do
      assert_equal('foo', ReopenedSubStruct.from_hash('superprop' => 'foo').serialize['superprop'])
    end

    it 'round trips child prop' do
      assert_equal('foo', ReopenedSubStruct.from_hash('subprop' => 'foo').serialize['subprop'])
    end

    it 'round trips prop from T::Props::Serializable mixin' do
      assert_equal('foo', ReopenedSubStruct.from_hash('mixinprop' => 'foo').serialize['mixinprop'])
    end

    it 'round trips prop from mixin which uses def self.included' do
      assert_equal('foo', ReopenedSubStruct.from_hash('concernprop' => 'foo').serialize['concernprop'])
    end
  end

  class NoPropsStruct < T::Struct
  end

  describe 'struct without props' do
    it 'round trips' do
      assert_equal({}, NoPropsStruct.from_hash({}).serialize)
    end
  end

  class CustomSerializedForm < T::Struct
    prop :prop, String, name: 'something_custom'
  end

  describe 'custom serialized form' do
    it 'round trips' do
      hash = CustomSerializedForm.new(prop: 'foo').serialize
      assert_equal({'something_custom' => 'foo'}, hash)
      assert_equal('foo', CustomSerializedForm.from_hash(hash).prop)
    end
  end

  class ArrayOfNilableStruct < T::Struct
    prop :prop, T::Array[T.nilable(MyEnum)]
  end

  describe 'with array of nilable enums' do
    it 'can deserialize non-nil' do
      assert_equal([MyEnum::FOO], ArrayOfNilableStruct.from_hash('prop' => ['foo']).prop)
    end

    it 'can deserialize nil' do
      assert_equal([nil], ArrayOfNilableStruct.from_hash('prop' => [nil]).prop)
    end
  end

  class ModulePropStruct < T::Struct
    module NonScalar
    end

    class ConcreteNonScalar
      include NonScalar
    end

    module Scalar
    end

    class ConcreteScalar
      include Scalar
    end

    prop :nonscalar, T.nilable(NonScalar)
    prop :scalar, T.nilable(Scalar)
  end

  describe 'with a module prop type' do
    before do
      T::Configuration.scalar_types = T::Configuration.scalar_types.keys + [ModulePropStruct::Scalar.name]
    end

    after do
      T::Configuration.scalar_types = nil
    end

    it 'is cloned on serde by default' do
      val = ModulePropStruct::ConcreteNonScalar.new
      T::Props::Utils.expects(:deep_clone).with(val).returns(val).at_least_once

      s = ModulePropStruct.new(nonscalar: val)
      assert_equal(val, ModulePropStruct.from_hash(s.serialize).nonscalar)
    end

    it 'is not cloned on serde if set as scalar' do
      val = ModulePropStruct::ConcreteScalar.new
      T::Props::Utils.expects(:deep_clone).never

      s = ModulePropStruct.new(scalar: val)
      assert_equal(val, ModulePropStruct.from_hash(s.serialize).scalar)
    end
  end

  class Hashlike < Hash
    def initialize
      @called = false
      super()
    end

    def [](key)
      @called = true
      super(key)
    end

    def was_called
      @called
    end
  end

  class StructForHashlike
    include T::Props::Serializable

    prop :stringprop, String
  end

  describe 'with a custom hash-like type' do
    it 'calls the overridden aref method' do
      h = Hashlike['stringprop', 'foo']
      assert_instance_of(Hashlike, h)
      obj = StructForHashlike.from_hash(h)
      assert_equal("foo", obj.stringprop)
      assert(h.was_called)
    end
  end

  class DefaultStringProp
    include T::Props::Serializable

    prop :stringprop, String, default: +"default"
  end

  describe 'with defaulted string props' do
    it 'does not share structure' do
      h = {}
      obj1 = DefaultStringProp.from_hash(h)
      obj2 = DefaultStringProp.from_hash(h)
      refute_equal(obj1.stringprop.object_id, obj2.stringprop.object_id)
    end

    it 'returns mutable string defaults from the lazily-eval\'d deserializer' do
      # The generated deserializer inlines the default as a bare string
      # literal, and the lazily-eval'd source must not carry a
      # frozen_string_literal prefix: that would freeze (and dedupe) the
      # literal, so instances would share one frozen default.
      obj1 = DefaultStringProp.from_hash({})
      refute_predicate(obj1.stringprop, :frozen?)
      obj1.stringprop << ' mutated'
      assert_equal('default', DefaultStringProp.from_hash({}).stringprop)
    end
  end

  class ComplexStruct < T::Struct
    prop :primitive, Integer
    prop :nilable, T.nilable(Integer)
    prop :nilable_on_read, T.nilable(Integer), raise_on_nil_write: true
    prop :primitive_default, Integer, default: 0
    prop :primitive_nilable_default, T.nilable(Integer), default: 0
    prop :factory, Integer, factory: -> { 0 }
    prop :primitive_array, T::Array[Integer]
    prop :array_default, T::Array[Integer], default: []
    prop :primitive_hash, T::Hash[String, Integer]
    prop :array_of_nilable, T::Array[T.nilable(Integer)]
    prop :nilable_array, T.nilable(T::Array[Integer])
    prop :substruct, MySerializable
    prop :nilable_substract, T.nilable(MySerializable)
    prop :default_substruct, MySerializable, default: MySerializable.from_hash({'name' => 'default'})
    prop :array_of_substruct, T::Array[MySerializable]
    prop :hash_of_substruct, T::Hash[String, MySerializable]
    prop :custom_type, CustomType
    prop :nilable_custom_type, T.nilable(CustomType)
    prop :default_custom_type, CustomType, default: CustomType.new
    prop :array_of_custom_type, T::Array[CustomType]
    prop :hash_of_custom_type_to_substruct, T::Hash[CustomType, MySerializable]
    prop :unidentified_type, Object
    prop :nilable_unidentified_type, T.nilable(Object)
    prop :array_of_unidentified_type, T::Array[Object]
    prop :defaulted_unidentified_type, Object, default: Object.new
    prop :hash_with_unidentified_types, T::Hash[Object, Object]
    prop :infinity_float, Float, default: Float::INFINITY
    prop :negative_infinity_float, Float, default: -Float::INFINITY
    prop :nan_float, Float, default: Float::NAN
    prop :enum, MyEnum
    prop :nilable_enum, T.nilable(MyEnum)
    prop :default_enum, MyEnum, default: MyEnum::FOO
    prop :deprecated_enum, Symbol, enum: %i[foo_one foo_two]
    prop :nilable_deprecated_enum, T.nilable(Symbol), enum: %i[foo_one foo_two]
    prop :default_deprecated_enum, Symbol, enum: %i[foo_one foo_two], default: :foo_one
  end

  it 'can serialize a complex object' do
    attributes = {
      primitive: 1,
      nilable_on_read: 1,
      primitive_array: [1],
      primitive_hash: {'1' => 1},
      array_of_nilable: [1, nil],
      substruct: MySerializable.from_hash({'name' => 'foo1'}),
      array_of_substruct: [MySerializable.from_hash({'name' => 'foo2'})],
      hash_of_substruct: {'3' => MySerializable.from_hash({'name' => 'foo3'})},
      custom_type: CustomType.deserialize('foo1'),
      array_of_custom_type: [CustomType.deserialize('foo2')],
      hash_of_custom_type_to_substruct: {CustomType.deserialize('foo3') => MySerializable.from_hash({'name' => 'foo4'})},
      unidentified_type: 1,
      array_of_unidentified_type: [1],
      hash_with_unidentified_types: {2 => 3},
      defaulted_unidentified_type: {3 => 4},
      enum: MyEnum::FOO,
      deprecated_enum: :foo_one,
    }

    assert_equal(
      {
        "primitive" => 1,
        "nilable_on_read" => 1,
        "primitive_default" => 0,
        "primitive_nilable_default" => 0,
        "factory" => 0,
        "primitive_array" => [1],
        "array_default" => [],
        "primitive_hash" => {"1" => 1},
        "array_of_nilable" => [1, nil],
        "substruct" => {"name" => "foo1"},
        "default_substruct" => {"name" => "default"},
        "array_of_substruct" => [{"name" => "foo2"}],
        "hash_of_substruct" => {"3" => {"name" => "foo3"}},
        "custom_type" => "foo1",
        "default_custom_type" => nil,
        "array_of_custom_type" => ["foo2"],
        "hash_of_custom_type_to_substruct" => {"foo3" => {"name" => "foo4"}},
        "unidentified_type" => 1,
        "array_of_unidentified_type" => [1],
        "defaulted_unidentified_type" => {3 => 4},
        "hash_with_unidentified_types" => {2 => 3},
        "infinity_float" => Float::INFINITY,
        "negative_infinity_float" => -Float::INFINITY,
        "nan_float" => Float::NAN,
        "enum" => "foo",
        "default_enum" => "foo",
        "deprecated_enum" => :foo_one,
        "default_deprecated_enum" => :foo_one,
      }, ComplexStruct.new(attributes).serialize(false)
    )
  end

  it 'can deserialize a complex object' do
    attributes = {
      'primitive' => 1,
      'nilable_on_read' => 1,
      'primitive_array' => [1],
      'primitive_hash' => {'1' => 1},
      'array_of_nilable' => [1, nil],
      'substruct' => {'name' => 'foo1'},
      'array_of_substruct' => [{'name' => 'foo2'}],
      'hash_of_substruct' => {'3' => {'name' => 'foo3'}},
      'custom_type' => 'foo1',
      'array_of_custom_type' => ['foo2'],
      'hash_of_custom_type_to_substruct' => {'foo3' => {'name' => 'foo4'}},
      'unidentified_type' => 1,
      'array_of_unidentified_type' => [1],
      'hash_with_unidentified_types' => {2 => 3},
      'defaulted_unidentified_type' => {3 => 4},
      'enum' => 'foo',
      'deprecated_enum' => :foo_one,
    }

    assert_equal(
      {
        "primitive" => 1,
        "nilable_on_read" => 1,
        "primitive_default" => 0,
        # "primitive_nilable_default"=>0, # Possible bug: This is not in the expected hash, but seems like it should be.
        "factory" => 0,
        "primitive_array" => [1],
        "array_default" => [],
        "primitive_hash" => {"1" => 1},
        "array_of_nilable" => [1, nil],
        "substruct" => {"name" => "foo1"},
        "default_substruct" => {"name" => "default"},
        "array_of_substruct" => [{"name" => "foo2"}],
        "hash_of_substruct" => {"3" => {"name" => "foo3"}},
        "custom_type" => "foo1",
        "default_custom_type" => nil,
        "array_of_custom_type" => ["foo2"],
        "hash_of_custom_type_to_substruct" => {"foo3" => {"name" => "foo4"}},
        "unidentified_type" => 1,
        "array_of_unidentified_type" => [1],
        "defaulted_unidentified_type" => {3 => 4},
        "hash_with_unidentified_types" => {2 => 3},
        "infinity_float" => Float::INFINITY,
        "negative_infinity_float" => -Float::INFINITY,
        "nan_float" => Float::NAN,
        "enum" => "foo",
        "default_enum" => "foo",
        "deprecated_enum" => :foo_one,
        "default_deprecated_enum" => :foo_one,
      }, ComplexStruct.from_hash(attributes).serialize(false)
    )
  end

  class DeferredEnum < T::Enum
    enums do
      One = new('one')
      Two = new('two')
    end
  end

  module DeferredEnums
    include T::Props::Plugin

    module DecoratorMethods
      attr_accessor :eager_enums

      def supports_lazy_enum_deserialization?
        true
      end

      def lazy_enum_deserialization?(instance)
        !eager_enums
      end
    end
  end

  class DeferredEnumDocument < T::InexactStruct
    include DeferredEnums
    EnumAlias = T.type_alias { T.nilable(DeferredEnum) }

    prop :required, DeferredEnum, name: 'stored'
    prop :optional, EnumAlias
    prop :hidden, T.nilable(DeferredEnum), without_accessors: true
    prop :label, String, default: 'label'
  end

  class DeferredEnumDefaults < T::Struct
    include DeferredEnums
    prop :defaulted, DeferredEnum, default: DeferredEnum::One
    prop :factory, DeferredEnum, factory: -> { DeferredEnum::Two }
    prop :optional, T.nilable(DeferredEnum), default: DeferredEnum::One
    prop :missing, T.nilable(DeferredEnum), raise_on_nil_write: true
  end

  class DeferredEnumParent < T::Struct
    prop :children, T::Array[DeferredEnumDocument]
    prop :by_name, T::Hash[String, DeferredEnumDocument]
  end

  class EagerEnumContainers < T::Struct
    include DeferredEnums
    prop :array, T::Array[DeferredEnum]
    prop :mapping, T::Hash[String, DeferredEnum]
    prop :union, T.any(DeferredEnum, String)
  end

  describe 'internal deferred enum deserialization' do
    after do
      DeferredEnumDocument.decorator.eager_enums = false
    end

    it 'defers conversion until direct or dynamic access and memoizes on frozen objects' do
      DeferredEnum.expects(:deserialize).never
      doc = DeferredEnumDocument.from_hash!('stored' => 'one')
      assert_nil(doc.instance_variable_get(:@required))
      assert_equal({'stored' => 'one', 'label' => 'label'}, doc.serialize)
      DeferredEnum.unstub(:deserialize)
      DeferredEnum.expects(:deserialize).with('one').once.returns(DeferredEnum::One)
      doc.freeze
      assert_same(DeferredEnum::One, doc.required)
      assert_same(DeferredEnum::One, doc.required)
      assert_same(DeferredEnum::One, doc.class.decorator.prop_get(doc, :required))
      assert_same(DeferredEnum::One, doc.class.decorator.get(doc, :required))
      assert_equal('one', doc.serialize.fetch('stored'))
      assert_nil(doc.instance_variable_get(:@required))
    end

    it 'preserves unknown values through serialization and unrelated writes, with fresh errors at each read' do
      doc = DeferredEnumDocument.from_hash!('stored' => 'unknown', 'optional' => 'unknown', 'hidden' => 'unknown')
      doc.label = 'changed'
      assert_equal('changed', doc.label)
      first = assert_raises(KeyError) { doc.required }
      second = assert_raises(KeyError) { doc.required }
      refute_same(first, second)
      assert_includes(first.message, 'DeferredEnumDocument#required')
      assert_raises(KeyError) { doc.class.decorator.prop_get(doc, :optional) }
      assert_raises(KeyError) { doc.class.decorator.get(doc, :hidden) }
      assert_equal({'stored' => 'unknown', 'optional' => 'unknown', 'hidden' => 'unknown', 'label' => 'changed'}, doc.serialize)
      assert_empty(doc.class.decorator.extra_props(doc))
    end

    it 'copies retained strings and never exposes them through inspection' do
      raw = +'unknown'
      doc = DeferredEnumDocument.from_hash('stored' => raw)
      raw.replace('changed')
      serialized = doc.serialize
      serialized['stored'].replace('also changed')
      assert_equal('unknown', doc.serialize.fetch('stored'))
      DeferredEnum.expects(:deserialize).never
      assert_includes(doc.inspect, 'required=<pending enum>')
      refute_includes(doc.inspect, 'unknown')
      refute_includes(doc.pretty_inspect, 'unknown')
    end

    it 'preserves redaction without passing pending raw values to custom inspection callbacks' do
      klass = Class.new(DeferredEnumDocument) do
        def self.contains_pii?
          true
        end

        prop :secret, T.nilable(DeferredEnum), sensitivity: ['private']
        prop :custom, T.nilable(DeferredEnum), inspect: ->(_value) { raise 'must not inspect pending values' }
      end
      doc = klass.from_hash('stored' => 'unknown', 'secret' => 'unknown', 'custom' => 'unknown')
      DeferredEnum.expects(:deserialize).never
      [doc.inspect, doc.pretty_inspect].each do |output|
        assert_includes(output, 'secret=<REDACTED private>')
        assert_includes(output, 'custom=<pending enum>')
        refute_includes(output, 'unknown')
      end
    end

    it 'invalidates pending and resolved values only after successful writes on every setter path' do
      %i[generated dynamic bound cached].each do |path|
        doc = DeferredEnumDocument.from_hash('stored' => 'unknown')
        write = lambda do |value|
          case path
          when :generated then doc.required = value
          when :dynamic then doc.class.decorator.prop_set(doc, :required, value)
          when :bound then doc.class.decorator.prop_rules(:required).fetch(:_bound_setter_proc).call(doc, value)
          when :cached then doc.class.decorator.props_without_defaults.fetch(:required).call(doc, value)
          end
        end
        assert_raises(TypeError) { write.call('invalid') }
        assert_equal('unknown', doc.serialize.fetch('stored'))
        write.call(DeferredEnum::One)
        assert_same(DeferredEnum::One, doc.required)
        assert_equal('one', doc.serialize.fetch('stored'))
        doc.deserialize('stored' => 'two')
        assert_same(DeferredEnum::Two, doc.required)
        write.call(DeferredEnum::One)
        assert_same(DeferredEnum::One, doc.required)
      end
    end

    it 'invalidates pending values through cached default setters' do
      defaults = DeferredEnumDefaults.from_hash('defaulted' => 'unknown')
      setter = defaults.class.decorator.props_with_defaults.fetch(:defaulted).bound_setter_proc
      assert_raises(TypeError) { setter.call(defaults, 'invalid') }
      assert_equal('unknown', defaults.serialize(false).fetch('defaulted'))
      setter.call(defaults, DeferredEnum::Two)
      assert_same(DeferredEnum::Two, defaults.defaulted)
    end

    it 'does not discard state when a frozen setter fails' do
      doc = DeferredEnumDocument.from_hash('stored' => 'unknown').freeze
      assert_raises(FrozenError) { doc.required = DeferredEnum::One }
      assert_equal('unknown', doc.serialize.fetch('stored'))
    end

    it 'supports nil assignment and dynamic writes without accessors' do
      doc = DeferredEnumDocument.from_hash('stored' => 'one', 'optional' => 'unknown', 'hidden' => 'unknown')
      doc.optional = nil
      doc.class.decorator.prop_set(doc, :hidden, DeferredEnum::Two)
      assert_nil(doc.optional)
      assert_same(DeferredEnum::Two, doc.class.decorator.prop_get(doc, :hidden))
      refute(doc.respond_to?(:hidden))
      assert_equal({'stored' => 'one', 'hidden' => 'two', 'label' => 'label'}, doc.serialize)
    end

    it 'copies sidecar containers independently for dup and clone, including frozen copies' do
      original = DeferredEnumDocument.from_hash('stored' => 'one').freeze
      [original.dup, original.clone].each do |copy|
        refute_same(original.instance_variable_get(:@_lazy_enum_values), copy.instance_variable_get(:@_lazy_enum_values))
        assert_same(DeferredEnum::One, copy.required)
        assert(original.class.decorator.lazy_enum_pending?(original, :required))
      end
      replacement = original.dup
      replacement.required = DeferredEnum::Two
      assert_equal('one', original.serialize.fetch('stored'))
      assert_equal('two', replacement.serialize.fetch('stored'))
    end

    it 'resets prior pending and resolved state on deserialization' do
      doc = DeferredEnumDocument.from_hash('stored' => 'one', 'optional' => 'unknown')
      assert_same(DeferredEnum::One, doc.required)
      doc.deserialize('stored' => 'two', 'optional' => nil)
      assert_same(DeferredEnum::Two, doc.required)
      assert_nil(doc.optional)
      doc.deserialize('stored' => 'one', 'optional' => 'one')
      doc.deserialize('stored' => 'two')
      assert_nil(doc.optional)
      assert_raises(RuntimeError) { doc.deserialize({}) }
    end

    it 'keeps the representation chosen at load time when the policy changes' do
      doc = DeferredEnumDocument.from_hash('stored' => 'unknown')
      DeferredEnumDocument.decorator.eager_enums = true
      assert_raises(KeyError) { DeferredEnumDocument.from_hash('stored' => 'unknown') }
      assert_equal('unknown', doc.serialize.fetch('stored'))
      assert_raises(KeyError) { doc.required }
      doc.deserialize('stored' => 'one')
      assert_nil(doc.instance_variable_get(:@_lazy_enum_values))
      assert_same(DeferredEnum::One, doc.required)
    end

    it 'preserves defaults, factories, nilability, missing-required behavior, and constructor validation' do
      doc = DeferredEnumDefaults.from_hash({})
      assert_same(DeferredEnum::One, doc.defaulted)
      assert_same(DeferredEnum::Two, doc.factory)
      assert_nil(doc.optional)
      assert_nil(doc.missing)
      assert_raises(TypeError) { DeferredEnumDocument.new(required: 'unknown') }
      assert_same(DeferredEnum::One, DeferredEnumDocument.new(required: DeferredEnum::One).required)
    end

    it 'constructs parents and nested collections eagerly but defers their enum leaves' do
      raw = {'stored' => 'unknown'}
      parent = DeferredEnumParent.from_hash('children' => [raw], 'by_name' => {'child' => raw})
      child = parent.children.fetch(0)
      assert_instance_of(DeferredEnumDocument, child)
      child.label = 'changed'
      assert_equal('unknown', parent.serialize.fetch('children').fetch(0).fetch('stored'))
      assert_equal('unknown', parent.serialize.fetch('by_name').fetch('child').fetch('stored'))
      assert_raises(KeyError) { child.required }
    end

    it 'leaves container and unusual union props ineligible' do
      assert(EagerEnumContainers.props.values.none? { |rules| rules[:_lazy_enum] })
      assert_raises(KeyError) { EagerEnumContainers.from_hash('array' => ['unknown'], 'hash' => {}, 'union' => 'text') }
    end

    it 'keeps ordinary serializable enum props eager by default' do
      assert_raises(KeyError) { EnumStruct.from_hash('enum' => 'unknown') }
      doc = DeferredEnumDocument.new(required: DeferredEnum::One)
      DeferredEnumDocument.decorator.expects(:prop_get).never
      assert_equal('label', doc.label)
    end

    it 'validates the exact new generated clauses and rejects changes to their helper calls' do
      decorator = DeferredEnumDocument.decorator
      %i[serialize deserialize].each do |mode|
        source = decorator.send("generate_#{mode}_source")
        T::Props::GeneratedCodeValidation.public_send("validate_#{mode}", source)
        invalid = source.sub(/__t_props_(?:serialize_lazy_enum|store_lazy_enum)/, 'unexpected_call')
        assert_raises(T::Props::GeneratedCodeValidation::ValidationError) do
          T::Props::GeneratedCodeValidation.public_send("validate_#{mode}", invalid)
        end
      end
    end
  end

  describe 'generated code' do
    describe 'serialize' do
      it 'validates' do
        src = ComplexStruct.decorator.send(:generate_serialize_source).to_s
        T::Props::GeneratedCodeValidation.validate_serialize(src)
      end

      it 'has meaningful validation which complains at lurky method invocation' do
        src = ComplexStruct.decorator.send(:generate_serialize_source).to_s
        src = src.sub(/\.transform_values\b/, '.something_suspicious')
        assert_raises(T::Props::GeneratedCodeValidation::ValidationError) do
          T::Props::GeneratedCodeValidation.validate_serialize(src)
        end
      end
    end

    describe 'deserialize' do
      it 'validates' do
        src = ComplexStruct.decorator.send(:generate_deserialize_source).to_s
        T::Props::GeneratedCodeValidation.validate_deserialize(src)
      end

      it 'has meaningful validation which complains at lurky method invocation' do
        src = ComplexStruct.decorator.send(:generate_deserialize_source).to_s
        src = src.sub(/\.default\b/, '.something_suspicious')
        assert_raises(T::Props::GeneratedCodeValidation::ValidationError) do
          T::Props::GeneratedCodeValidation.validate_deserialize(src)
        end
      end

      describe 'with custom module_name_mangler' do
        before do
          T::Configuration.module_name_mangler = ->(type) { "MANGLED::#{type}" }
        end

        after do
          T::Configuration.module_name_mangler = nil
        end

        it 'mangles the custom type names in generated code' do
          src = ComplexStruct.decorator.send(:generate_deserialize_source).to_s
          T::Props::GeneratedCodeValidation.validate_deserialize(src)
          assert_includes(src, "MANGLED::#{MySerializable}")
          assert_includes(src, "MANGLED::#{CustomType}")
        end
      end
    end

    describe 'disabling evaluation' do
      it 'works' do
        T::Props::HasLazilySpecializedMethods.disable_lazy_evaluation!

        m = Class.new do
          include T::Props::Serializable

          prop :foo, T.nilable(String)
        end

        assert_raises(T::Props::HasLazilySpecializedMethods::SourceEvaluationDisabled) do
          m.new.serialize
        end

        # Explicit call is still ok
        m.decorator.eagerly_define_lazy_methods!
      end

      after do
        T::Props::HasLazilySpecializedMethods.remove_instance_variable(:@lazy_evaluation_disabled)
      end
    end
  end

  class StructWithFloat < T::Struct
    const :my_float, Float
  end

  it "coerces raw values to Float if the prop's type is Float" do
    swf1 = StructWithFloat.new(my_float: 1.0)

    serialized_hash = swf1.serialize
    # Ruby happens to serialize Float's with a `.0`, but JSON doesn't
    # distinguish number types, so it's equally fine to omit it, and the
    # process of serializing and deserializing is free to drop that
    # information.
    #
    # To get Ruby to omit it, we change it to an Integer before calling `.to_json`
    serialized_hash['my_float'] = 1
    json = serialized_hash.to_json

    assert_equal('{"my_float":1}', json)

    deserialized_hash = JSON.parse(json)

    assert_instance_of(Integer, deserialized_hash['my_float'])
    assert_equal(1, deserialized_hash['my_float'])

    swf2 = StructWithFloat.from_hash(deserialized_hash)

    assert_instance_of(Float, swf2.my_float)
    assert_in_delta(1.0, swf2.my_float, 0.0001)
  end

  class DynamicProps
    include T::Props::Serializable
    include T::Props::WeakConstructor

    prop :nilstring, T.nilable(String)
  end

  describe 'dynamic props' do
    it 'serializes when new props are added' do
      obj = DynamicProps.new(nilstring: 'foo')
      h = obj.serialize

      assert_equal('foo', h['nilstring'])

      DynamicProps.prop(:arrayprop, T::Array[String], default: ['default'])

      assert_raises(TypeError) do
        obj.serialize
      end

      obj.arrayprop = ['bar']
      h = obj.serialize
      assert_equal(['bar'], h['arrayprop'])
    end
  end

  class ConstDefault < T::Struct
    const :required_at_some_point, NilClass, default: nil
    const :still_required_prop, Integer
  end

  describe 'const NilClass' do
    it 'round-trip serializes' do
      h = {'still_required_prop' => 5}
      x = ConstDefault.from_hash!(h)
      assert_nil(x.required_at_some_point)
      x = x.with(still_required_prop: 6)
      assert_nil(x.required_at_some_point)
    end
  end

  class MuckAboutWithPropInternals
    include T::Props::Serializable
    include T::Props::WeakConstructor

    prop :nilstring, T.nilable(String)
  end

  # These tests are gross, but they are the only way certain exceptions are ever
  # going to be raised from the {de,}serialization generation process.
  #
  # Safe names are (currently) defined as /\A[A-Za-z_][A-Za-z0-9_-]*\z/.
  # We can't test everything outside of this set, but we can make a pass over
  # non-letter ASCII and get some coverage.
  DISALLOWED_CHARS = '!@#$%^&*()[{}]\|;:\'",<.>/?`~'.chars
  DISALLOWED_PREFIXES = DISALLOWED_CHARS + DISALLOWED_CHARS.map { |c| "a#{c}" }

  describe 'prop name safety checks' do
    it "catches when a prop name doesn't pass safe name checks" do
      DISALLOWED_PREFIXES.each do |c|
        bad_prop_name = :"#{c}nilstring"
        props = MuckAboutWithPropInternals.decorator.instance_variable_get(:@props)
        refute_nil(props)
        refute_nil(props[:nilstring])
        MuckAboutWithPropInternals.decorator.instance_variable_set(:@props, props.merge(bad_prop_name => props[:nilstring]))
        assert_raises(RuntimeError) do
          MuckAboutWithPropInternals.from_hash({})
        end
        MuckAboutWithPropInternals.decorator.instance_variable_set(:@props, props)
      end
    end

    it "catches when a hash key doesn't pass safe name checks" do
      DISALLOWED_PREFIXES.each do |c|
        ok_prop_name = :nilstring2
        bad_hash_key = "#{c}nilstring"
        props = MuckAboutWithPropInternals.decorator.instance_variable_get(:@props)
        refute_nil(props)
        refute_nil(props[:nilstring])
        bad_rules = props[:nilstring].merge(serialized_form: bad_hash_key)
        MuckAboutWithPropInternals.decorator.instance_variable_set(:@props, props.merge(ok_prop_name => bad_rules))
        assert_raises(RuntimeError) do
          MuckAboutWithPropInternals.from_hash({})
        end
        MuckAboutWithPropInternals.decorator.instance_variable_set(:@props, props)
      end
    end

    it "catches when the accessor key doesn't begin with @" do
      DISALLOWED_PREFIXES.reject { |c| c == "@" }.each do |c|
        ok_prop_name = :nilstring2
        bad_accessor_key = :"#{c}nilstring"
        props = MuckAboutWithPropInternals.decorator.instance_variable_get(:@props)
        refute_nil(props)
        refute_nil(props[:nilstring])
        bad_rules = props[:nilstring].merge(accessor_key: bad_accessor_key)
        MuckAboutWithPropInternals.decorator.instance_variable_set(:@props, props.merge(ok_prop_name => bad_rules))
        assert_raises(RuntimeError) do
          MuckAboutWithPropInternals.from_hash({})
        end
        MuckAboutWithPropInternals.decorator.instance_variable_set(:@props, props)
      end
    end

    it "catches when the accessor key doesn't pass safe name checks" do
      DISALLOWED_PREFIXES.each do |_c|
        ok_prop_name = :nilstring2
        bad_accessor_key = :"@!nilstring"
        props = MuckAboutWithPropInternals.decorator.instance_variable_get(:@props)
        refute_nil(props)
        refute_nil(props[:nilstring])
        bad_rules = props[:nilstring].merge(accessor_key: bad_accessor_key)
        MuckAboutWithPropInternals.decorator.instance_variable_set(:@props, props.merge(ok_prop_name => bad_rules))
        assert_raises(RuntimeError) do
          MuckAboutWithPropInternals.from_hash({})
        end
        MuckAboutWithPropInternals.decorator.instance_variable_set(:@props, props)
      end
    end
  end
end
