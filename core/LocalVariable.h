#ifndef RUBY_TYPER_LOCALVARIABLE_H
#define RUBY_TYPER_LOCALVARIABLE_H

#include "core/NameRef.h"
#include "core/Names.h"

namespace sorbet::core {

class LocalVariable final {
public:
    NameRef _name;
    u4 unique;

    LocalVariable(NameRef name, u4 unique) : _name(name), unique(unique) {}

    LocalVariable() = default;

    bool exists() const;

    bool isSyntheticTemporary(const GlobalState &gs) const;

    bool isAliasForGlobal(const GlobalState &gs) const;

    LocalVariable(const LocalVariable &) = default;

    LocalVariable(LocalVariable &&) = default;

    LocalVariable &operator=(LocalVariable &&) = default;

    LocalVariable &operator=(const LocalVariable &) = default;

    bool operator==(const LocalVariable &rhs) const;

    bool operator!=(const LocalVariable &rhs) const;

    inline bool operator<(const LocalVariable &rhs) const {
        if (this->_name.id() < rhs._name.id()) {
            return true;
        }
        if (this->_name.id() > rhs._name.id()) {
            return false;
        }
        return this->unique < rhs.unique;
    }

    static inline LocalVariable noVariable() {
        return LocalVariable(NameRef::noName(), 0);
    }

    static inline LocalVariable blockCall() {
        return LocalVariable(Names::blockCall(), 0);
    }

    std::string showRaw(const GlobalState &gs) const;
    std::string toString(const GlobalState &gs) const;
    static inline LocalVariable selfVariable() {
        return LocalVariable(Names::selfLocal(), 0);
    }
};

CheckSize(LocalVariable, 8, 4);

template <typename H> H AbslHashValue(H h, const LocalVariable &m) {
    return H::combine(std::move(h), m._name, m.unique);
}
} // namespace sorbet::core
#endif // RUBY_TYPER_LOCALVARIABLE_H