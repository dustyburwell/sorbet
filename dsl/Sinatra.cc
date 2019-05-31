#include "dsl/Sinatra.h"
#include "ast/Helpers.h"
#include "ast/ast.h"
#include "core/Context.h"
#include "core/Names.h"
#include "core/core.h"
#include "core/errors/dsl.h"
#include "dsl/dsl.h"

using namespace std;

namespace sorbet::dsl {

vector<unique_ptr<ast::Expression>> Sinatra::replaceDSL(core::MutableContext ctx, ast::MethodDef *mdef) {
    vector<unique_ptr<ast::Expression>> empty;

    if (ctx.state.runningUnderAutogen) {
        // TODO(jez) Verify whether this DSL pass is safe to run in for autogen
        return empty;
    }

    if (mdef->name != core::Names::registered()) {
        return empty;
    }
    if (!mdef->isSelf()) {
        return empty;
    }

    mdef->name = core::Names::instanceRegistered();
    mdef->flags &= ~ast::MethodDef::SelfMethod;

    vector<unique_ptr<ast::Expression>> ret;
    auto loc = mdef->loc;

    ret.emplace_back(ast::MK::Send1(
        loc, ast::MK::Self(loc), core::Names::include(),
        ast::MK::UnresolvedConstant(
            loc, ast::MK::UnresolvedConstant(loc, ast::MK::EmptyTree(), core::Symbols::Sinatra().data(ctx)->name),
            core::Symbols::SinatraBase().data(ctx)->name)));

    auto inseq = ast::cast_tree<ast::InsSeq>(mdef->rhs.get());
    if (inseq) {
        auto stats = std::move(inseq->stats);
        inseq->stats.clear();
        for (auto &stat : stats) {
            typecase(
                stat.get(),
                [&](ast::Send *send) {
                    if (send->fun == core::Names::helpers() && send->args.size() == 1 &&
                        ast::isa_tree<ast::UnresolvedConstantLit>(send->args[0].get())) {
                        ret.emplace_back(ast::MK::Send1(send->loc, ast::MK::Self(loc), core::Names::include(),
                                                        std::move(send->args[0])));
                    } else {
                        inseq->stats.emplace_back(std::move(stat));
                    }
                },
                [&](ast::Expression *e) { inseq->stats.emplace_back(std::move(stat)); });
        }
        if (inseq->stats.empty()) {
            mdef->rhs = std::move(inseq->expr);
        }
    }

    ret.emplace_back(ast::MK::Method(loc, loc, core::Names::instanceRegistered(), std::move(mdef->args),
                                     std::move(mdef->rhs), ast::MethodDef::DSLSynthesized));

    return ret;
}

}; // namespace sorbet::dsl