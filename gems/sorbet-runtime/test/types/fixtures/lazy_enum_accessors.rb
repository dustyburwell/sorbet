# frozen_string_literal: true
# typed: true

require_relative '../../../lib/sorbet-runtime'

class LazyAccessorEnum < T::Enum
  enums do
    Known = new('known')
  end
end

module LazyAccessorPolicy
  include T::Props::Plugin

  module DecoratorMethods
    def supports_lazy_enum_deserialization?
      true
    end

    def lazy_enum_deserialization?(instance)
      true
    end
  end
end

class LazyAccessorDocument < T::Struct
  include LazyAccessorPolicy

  prop :value, LazyAccessorEnum
  prop :optional, T.nilable(LazyAccessorEnum)
  prop :ordinary, String, default: 'ordinary'
end

class LazyAccessorCaller
  extend T::Sig

  sig { params(doc: LazyAccessorDocument).returns(LazyAccessorEnum) }
  def self.read(doc)
    doc.value
  end

  sig { params(doc: LazyAccessorDocument, value: LazyAccessorEnum).void }
  def self.write(doc, value)
    doc.value = value
  end

  sig { params(doc: LazyAccessorDocument).returns(T.nilable(LazyAccessorEnum)) }
  def self.read_optional(doc)
    doc.optional
  end

  sig { params(doc: LazyAccessorDocument, value: T.nilable(LazyAccessorEnum)).void }
  def self.write_optional(doc, value)
    doc.optional = value
  end

  sig { params(doc: LazyAccessorDocument).returns(String) }
  def self.read_ordinary(doc)
    doc.ordinary
  end
end

module LazyAccessorGuard
  def value
    Kernel.raise 'restricted'
  end
end
