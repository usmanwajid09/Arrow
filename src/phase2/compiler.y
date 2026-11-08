%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ast.h"
#include "sema.h"

int yylex(void);
void yyerror(const char *msg);
extern FILE *yyin;
static Node *program_root;
%}

%locations
%define parse.error verbose
%expect 0

%union {
    long  ival;
    char *str;
    Node *node;
}

%token <ival> INT
%token <str>  ID
%token FN "fn" LOOP "loop" IN "in" WHEN "when" OTHERWISE "otherwise"
%token GIVE "give" SHOW "show" NEW "new" LEN "len" READ "read"
%token ARROW "=>" DOTDOT ".." LE "<=" GE ">=" EQ "==" NE "!="

%type <node> functions function params param_list param block stmts stmt when_stmt
%type <node> expr list list_ne lvalue

%left '|'
%left '&'
%left EQ NE
%left '<' '>' LE GE
%left '+' '-'
%left '*' '/' '%'
%precedence UMINUS '~'

%%

program
    : functions                         { program_root = $1; }
    ;

functions
    : function                          { $$ = $1; }
    | functions function                { $$ = ast_append($1, $2); }
    ;

function
    : FN ID '(' params ')' block        { $$ = ast_new(N_FN, @1.first_line); $$->name = $2; $$->a = $4; $$->b = $6; }
    ;

params
    : %empty                            { $$ = NULL; }
    | param_list                        { $$ = $1; }
    ;

param_list
    : param                             { $$ = $1; }
    | param_list ',' param              { $$ = ast_append($1, $3); }
    ;

param
    : ID                                { $$ = ast_new(N_PARAM, @1.first_line); $$->name = $1; $$->ival = 0; }
    | ID '[' ']'                        { $$ = ast_new(N_PARAM, @1.first_line); $$->name = $1; $$->ival = 1; }
    ;

block
    : '{' stmts '}'                     { $$ = ast_new(N_BLOCK, @1.first_line); $$->a = $2; }
    ;

stmts
    : %empty                            { $$ = NULL; }
    | stmts stmt                        { $$ = ast_append($1, $2); }
    ;

stmt
    : expr ARROW lvalue ';'             { $$ = ast_new(N_ASSIGN, @2.first_line); $$->a = $1; $$->b = $3; }
    | expr ARROW SHOW ';'               { $$ = ast_new(N_SHOW, @2.first_line); $$->a = $1; }
    | ID '(' list ')' ';'               { Node *c = ast_new(N_CALL, @1.first_line); c->name = $1; c->a = $3;
                                          $$ = ast_new(N_EXPRSTMT, @1.first_line); $$->a = c; }
    | LOOP expr block                   { $$ = ast_new(N_LOOP, @1.first_line); $$->a = $2; $$->b = $3; }
    | LOOP ID IN expr DOTDOT expr block { $$ = ast_new(N_RANGE, @1.first_line); $$->name = $2; $$->a = $4; $$->b = $6; $$->c = $7; }
    | when_stmt                         { $$ = $1; }
    | GIVE expr ';'                     { $$ = ast_new(N_GIVE, @1.first_line); $$->a = $2; }
    | error ';'                         { $$ = NULL; yyerrok; }
    ;

when_stmt
    : WHEN expr block                   { $$ = ast_new(N_WHEN, @1.first_line); $$->a = $2; $$->b = $3; }
    | WHEN expr block OTHERWISE block   { $$ = ast_new(N_WHEN, @1.first_line); $$->a = $2; $$->b = $3; $$->c = $5; }
    | WHEN expr block OTHERWISE when_stmt
                                        { Node *e = ast_new(N_BLOCK, @4.first_line); e->a = $5;
                                          $$ = ast_new(N_WHEN, @1.first_line); $$->a = $2; $$->b = $3; $$->c = e; }
    ;

lvalue
    : ID                                { $$ = ast_new(N_VAR, @1.first_line); $$->name = $1; }
    | ID '[' expr ']'                   { $$ = ast_new(N_INDEX, @1.first_line); $$->name = $1; $$->a = $3; }
    ;

expr
    : INT                               { $$ = ast_new(N_INT, @1.first_line); $$->ival = $1; }
    | ID                                { $$ = ast_new(N_VAR, @1.first_line); $$->name = $1; }
    | ID '[' expr ']'                   { $$ = ast_new(N_INDEX, @1.first_line); $$->name = $1; $$->a = $3; }
    | ID '(' list ')'                   { $$ = ast_new(N_CALL, @1.first_line); $$->name = $1; $$->a = $3; }
    | NEW '[' expr ']'                  { $$ = ast_new(N_NEW, @1.first_line); $$->a = $3; }
    | '[' list ']'                      { $$ = ast_new(N_ARRLIT, @1.first_line); $$->a = $2; }
    | LEN '(' expr ')'                  { $$ = ast_new(N_LEN, @1.first_line); $$->a = $3; }
    | READ '(' ')'                      { $$ = ast_new(N_READ, @1.first_line); }
    | '(' expr ')'                      { $$ = $2; }
    | expr '+' expr                     { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_ADD; $$->a = $1; $$->b = $3; }
    | expr '-' expr                     { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_SUB; $$->a = $1; $$->b = $3; }
    | expr '*' expr                     { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_MUL; $$->a = $1; $$->b = $3; }
    | expr '/' expr                     { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_DIV; $$->a = $1; $$->b = $3; }
    | expr '%' expr                     { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_MOD; $$->a = $1; $$->b = $3; }
    | expr '<' expr                     { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_LT; $$->a = $1; $$->b = $3; }
    | expr LE expr                      { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_LE; $$->a = $1; $$->b = $3; }
    | expr '>' expr                     { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_GT; $$->a = $1; $$->b = $3; }
    | expr GE expr                      { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_GE; $$->a = $1; $$->b = $3; }
    | expr EQ expr                      { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_EQ; $$->a = $1; $$->b = $3; }
    | expr NE expr                      { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_NE; $$->a = $1; $$->b = $3; }
    | expr '&' expr                     { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_AND; $$->a = $1; $$->b = $3; }
    | expr '|' expr                     { $$ = ast_new(N_BIN, @2.first_line); $$->op = OP_OR; $$->a = $1; $$->b = $3; }
    | '-' expr %prec UMINUS             { $$ = ast_new(N_UN, @1.first_line); $$->op = OP_NEG; $$->a = $2; }
    | '~' expr                          { $$ = ast_new(N_UN, @1.first_line); $$->op = OP_NOT; $$->a = $2; }
    ;

list
    : %empty                            { $$ = NULL; }
    | list_ne                           { $$ = $1; }
    ;

list_ne
    : expr                              { $$ = $1; }
    | list_ne ',' expr                  { $$ = ast_append($1, $3); }
    ;

%%

void yyerror(const char *msg)
{
    arrow_error(yylloc.first_line, "%s", msg);
}

/* =====================================================================
 *  PHASE 2 - THE AOT COMPILER
 *
 *  The grammar above is the same as in Phase 1.  Instead of executing the
 *  syntax tree, the C code below (still part of this Bison file) translates
 *  it into LLVM IR using the LLVM-C API.  The IR is optimized by LLVM,
 *  compiled to an object file, and linked with the C runtime into an
 *  executable (ahead-of-time compilation).
 *
 *  Every Arrow integer is an i64.  An array is a ptr to an i64 block whose
 *  word 0 is the length.  Every Arrow function f becomes the LLVM function
 *  f_<name>; a small C-ABI  main  calls f_main.
 * ===================================================================== */

#include <unistd.h>
#include <sys/wait.h>
#include <libgen.h>
#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/Error.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/Transforms/PassBuilder.h>
#include "bce.h"

#ifndef ARROW_RT_OBJ
#define ARROW_RT_OBJ "build/arrow_rt.o"
#endif

static LLVMContextRef ctx;
static LLVMModuleRef  mod;
static LLVMBuilderRef B;
static LLVMTypeRef i64T, i32T, i1T, ptrT, voidT;

typedef struct { LLVMValueRef fn; LLVMTypeRef ty; } RtFn;
static RtFn rt_oob, rt_new, rt_show, rt_read, rt_div, rt_mod;
static LLVMValueRef g_empty;
static unsigned invariant_kind;
static LLVMTargetMachineRef tm;
static char *triple;

static LLVMValueRef cur_fn;
static LLVMBasicBlockRef entry_bb;
static LLVMValueRef *slots;
static Node *cur_node;

static void fatal(const char *what, const char *detail)
{
    fprintf(stderr, "arrowc: %s%s%s\n", what, detail ? ": " : "", detail ? detail : "");
    exit(2);
}

/* ---------- small helpers ---------- */
static RtFn declare_rt(const char *name, LLVMTypeRef ret, LLVMTypeRef *ps, unsigned n, int noreturn)
{
    RtFn r;
    r.ty = LLVMFunctionType(ret, ps, n, 0);
    r.fn = LLVMAddFunction(mod, name, r.ty);
    if (noreturn) {
        unsigned kind = LLVMGetEnumAttributeKindForName("noreturn", 8);
        LLVMAddAttributeAtIndex(r.fn, LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(ctx, kind, 0));
    }
    return r;
}

static LLVMValueRef call_rt(RtFn f, LLVMValueRef *args, unsigned n)
{
    return LLVMBuildCall2(B, f.ty, f.fn, args, n, LLVMGetReturnType(f.ty) == voidT ? "" : "rt");
}

static LLVMValueRef c64(long v) { return LLVMConstInt(i64T, (unsigned long long)v, 1); }

static LLVMBasicBlockRef new_block(const char *name)
{
    return LLVMAppendBasicBlockInContext(ctx, cur_fn, name);
}

static int terminated(void)
{
    return LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(B)) != NULL;
}

/* allocas live in the entry block so that LLVM's mem2reg/SROA can promote them to SSA registers */
static LLVMValueRef entry_alloca(LLVMTypeRef t, const char *name)
{
    LLVMBuilderRef tb = LLVMCreateBuilderInContext(ctx);
    LLVMValueRef first = LLVMGetFirstInstruction(entry_bb), a;
    if (first) LLVMPositionBuilderBefore(tb, first);
    else       LLVMPositionBuilderAtEnd(tb, entry_bb);
    a = LLVMBuildAlloca(tb, t, name);
    LLVMDisposeBuilder(tb);
    return a;
}

/* the length of an array never changes, so the load of the header word is marked invariant;
   this lets LLVM hoist it out of loops */
static LLVMValueRef load_len(LLVMValueRef arr)
{
    LLVMValueRef l = LLVMBuildLoad2(B, i64T, arr, "len");
    LLVMSetMetadata(l, invariant_kind, LLVMMetadataAsValue(ctx, LLVMMDNodeInContext2(ctx, NULL, 0)));
    return l;
}

static LLVMValueRef to_bool(LLVMValueRef v) { return LLVMBuildICmp(B, LLVMIntNE, v, c64(0), "tobool"); }
static LLVMValueRef from_bool(LLVMValueRef b) { return LLVMBuildZExt(B, b, i64T, "frombool"); }

/* ---------- expressions ---------- */
static LLVMValueRef cg_expr(Node *e);

/* address of a[idx], with the bounds check unless the optimizer proved it unnecessary */
static LLVMValueRef cg_elem_addr(Node *ix)
{
    LLVMValueRef arr = LLVMBuildLoad2(B, ptrT, slots[ix->slot], "arr");
    LLVMValueRef idx = cg_expr(ix->a), off;

    if (!ix->safe) {
        LLVMValueRef len = load_len(arr);
        LLVMValueRef bad = LLVMBuildICmp(B, LLVMIntUGE, idx, len, "oob");   /* unsigned: also catches idx < 0 */
        LLVMBasicBlockRef fail = new_block("oob"), ok = new_block("inb");
        LLVMValueRef args[3];
        LLVMBuildCondBr(B, bad, fail, ok);
        LLVMPositionBuilderAtEnd(B, fail);
        args[0] = idx; args[1] = len; args[2] = c64(ix->line);
        call_rt(rt_oob, args, 3);
        LLVMBuildUnreachable(B);
        LLVMPositionBuilderAtEnd(B, ok);
    }
    off = LLVMBuildAdd(B, idx, c64(1), "off");
    return LLVMBuildGEP2(B, i64T, arr, &off, 1, "elt");
}

static LLVMValueRef cg_short_circuit(Node *e)
{
    int is_and = (e->op == OP_AND);
    LLVMValueRef lhs = to_bool(cg_expr(e->a)), rhs, phi;
    LLVMBasicBlockRef start = LLVMGetInsertBlock(B);
    LLVMBasicBlockRef rhs_bb = new_block(is_and ? "and.rhs" : "or.rhs");
    LLVMBasicBlockRef end_bb = new_block(is_and ? "and.end" : "or.end");
    LLVMBasicBlockRef rhs_end;
    LLVMValueRef vals[2];
    LLVMBasicBlockRef blks[2];

    if (is_and) LLVMBuildCondBr(B, lhs, rhs_bb, end_bb);
    else        LLVMBuildCondBr(B, lhs, end_bb, rhs_bb);
    LLVMPositionBuilderAtEnd(B, rhs_bb);
    rhs = to_bool(cg_expr(e->b));
    rhs_end = LLVMGetInsertBlock(B);            /* the right operand may have created blocks */
    LLVMBuildBr(B, end_bb);
    LLVMPositionBuilderAtEnd(B, end_bb);
    phi = LLVMBuildPhi(B, i1T, "sc");
    vals[0] = LLVMConstInt(i1T, is_and ? 0 : 1, 0); blks[0] = start;
    vals[1] = rhs;                                  blks[1] = rhs_end;
    LLVMAddIncoming(phi, vals, blks, 2);
    return from_bool(phi);
}

static LLVMValueRef cg_expr(Node *e)
{
    LLVMValueRef a, b, args[8];
    Node *p;
    unsigned i, n;

    switch (e->kind) {
    case N_INT:
        return c64(e->ival);
    case N_VAR:
        return LLVMBuildLoad2(B, e->type == T_ARR ? ptrT : i64T, slots[e->slot], e->name);
    case N_INDEX:
        return LLVMBuildLoad2(B, i64T, cg_elem_addr(e), "elem");
    case N_LEN:
        return load_len(cg_expr(e->a));
    case N_READ:
        args[0] = c64(e->line);
        return call_rt(rt_read, args, 1);
    case N_NEW:
        args[0] = cg_expr(e->a);
        args[1] = c64(e->line);
        return call_rt(rt_new, args, 2);
    case N_ARRLIT: {
        LLVMValueRef arr;
        n = (unsigned)ast_count(e->a);
        args[0] = c64(n);
        args[1] = c64(e->line);
        arr = call_rt(rt_new, args, 2);
        for (p = e->a, i = 0; p; p = p->next, i++) {
            LLVMValueRef v = cg_expr(p), off = c64(i + 1), addr;
            addr = LLVMBuildGEP2(B, i64T, arr, &off, 1, "init");
            LLVMBuildStore(B, v, addr);
        }
        return arr;
    }
    case N_CALL: {
        LLVMValueRef f = (LLVMValueRef)e->fn->aux;
        LLVMValueRef *av;
        n = (unsigned)ast_count(e->a);
        av = malloc((n ? n : 1) * sizeof *av);
        for (p = e->a, i = 0; p; p = p->next, i++) av[i] = cg_expr(p);
        a = LLVMBuildCall2(B, LLVMGlobalGetValueType(f), f, av, n, "call");
        free(av);
        return a;
    }
    case N_UN:
        a = cg_expr(e->a);
        if (e->op == OP_NEG) return LLVMBuildNeg(B, a, "neg");
        return from_bool(LLVMBuildICmp(B, LLVMIntEQ, a, c64(0), "not"));
    case N_BIN:
        if (e->op == OP_AND || e->op == OP_OR) return cg_short_circuit(e);
        a = cg_expr(e->a);
        b = cg_expr(e->b);
        switch (e->op) {
        case OP_ADD: return LLVMBuildAdd(B, a, b, "add");
        case OP_SUB: return LLVMBuildSub(B, a, b, "sub");
        case OP_MUL: return LLVMBuildMul(B, a, b, "mul");
        case OP_DIV:
        case OP_MOD:
            if (e->b->kind == N_INT && e->b->ival != 0 && e->b->ival != -1)
                return e->op == OP_DIV ? LLVMBuildSDiv(B, a, b, "div") : LLVMBuildSRem(B, a, b, "rem");
            args[0] = a; args[1] = b; args[2] = c64(e->line);
            return call_rt(e->op == OP_DIV ? rt_div : rt_mod, args, 3);
        case OP_LT: return from_bool(LLVMBuildICmp(B, LLVMIntSLT, a, b, "lt"));
        case OP_LE: return from_bool(LLVMBuildICmp(B, LLVMIntSLE, a, b, "le"));
        case OP_GT: return from_bool(LLVMBuildICmp(B, LLVMIntSGT, a, b, "gt"));
        case OP_GE: return from_bool(LLVMBuildICmp(B, LLVMIntSGE, a, b, "ge"));
        case OP_EQ: return from_bool(LLVMBuildICmp(B, LLVMIntEQ, a, b, "eq"));
        case OP_NE: return from_bool(LLVMBuildICmp(B, LLVMIntNE, a, b, "ne"));
        default: break;
        }
        break;
    default:
        break;
    }
    fatal("internal error", "bad expression in code generator");
    return NULL;
}

/* ---------- statements ---------- */
static void cg_list(Node *s);

static void cg_stmt(Node *s)
{
    switch (s->kind) {
    case N_ASSIGN: {
        Node *lv = s->b;
        LLVMValueRef v = cg_expr(s->a);          /* value first, then the index (as in the interpreter) */
        if (lv->kind == N_VAR) LLVMBuildStore(B, v, slots[lv->slot]);
        else                   LLVMBuildStore(B, v, cg_elem_addr(lv));
        break;
    }
    case N_SHOW: {
        LLVMValueRef args[1];
        args[0] = cg_expr(s->a);
        call_rt(rt_show, args, 1);
        break;
    }
    case N_EXPRSTMT:
        cg_expr(s->a);
        break;
    case N_BLOCK:
        cg_list(s->a);
        break;
    case N_GIVE:
        LLVMBuildRet(B, cg_expr(s->a));
        LLVMPositionBuilderAtEnd(B, new_block("after.give"));   /* statements after 'give' are dead code */
        break;
    case N_WHEN: {
        LLVMBasicBlockRef then_bb = new_block("then"), end_bb = new_block("endwhen");
        LLVMBasicBlockRef else_bb = s->c ? new_block("otherwise") : end_bb;
        LLVMBuildCondBr(B, to_bool(cg_expr(s->a)), then_bb, else_bb);
        LLVMPositionBuilderAtEnd(B, then_bb);
        cg_list(s->b->a);
        if (!terminated()) LLVMBuildBr(B, end_bb);
        if (s->c) {
            LLVMPositionBuilderAtEnd(B, else_bb);
            cg_list(s->c->a);
            if (!terminated()) LLVMBuildBr(B, end_bb);
        }
        LLVMPositionBuilderAtEnd(B, end_bb);
        break;
    }
    case N_LOOP: {
        LLVMBasicBlockRef cond_bb = new_block("while.cond"), body_bb = new_block("while.body"), end_bb = new_block("while.end");
        LLVMBuildBr(B, cond_bb);
        LLVMPositionBuilderAtEnd(B, cond_bb);
        LLVMBuildCondBr(B, to_bool(cg_expr(s->a)), body_bb, end_bb);
        LLVMPositionBuilderAtEnd(B, body_bb);
        cg_list(s->b->a);
        if (!terminated()) LLVMBuildBr(B, cond_bb);
        LLVMPositionBuilderAtEnd(B, end_bb);
        break;
    }
    case N_RANGE: {
        LLVMValueRef lo = cg_expr(s->a), hi = cg_expr(s->b);   /* both evaluated once, before the loop */
        LLVMValueRef ctr = entry_alloca(i64T, "ctr"), c, next;
        LLVMBasicBlockRef cond_bb = new_block("for.cond"), body_bb = new_block("for.body"), end_bb = new_block("for.end");
        LLVMBuildStore(B, lo, ctr);
        LLVMBuildBr(B, cond_bb);
        LLVMPositionBuilderAtEnd(B, cond_bb);
        c = LLVMBuildLoad2(B, i64T, ctr, "i");
        LLVMBuildCondBr(B, LLVMBuildICmp(B, LLVMIntSLT, c, hi, "inrange"), body_bb, end_bb);
        LLVMPositionBuilderAtEnd(B, body_bb);
        LLVMBuildStore(B, c, slots[s->slot]);
        cg_list(s->c->a);
        if (!terminated()) {
            next = LLVMBuildAdd(B, LLVMBuildLoad2(B, i64T, ctr, "i"), c64(1), "next");
            LLVMBuildStore(B, next, ctr);
            LLVMBuildBr(B, cond_bb);
        }
        LLVMPositionBuilderAtEnd(B, end_bb);
        break;
    }
    default:
        fatal("internal error", "bad statement in code generator");
    }
}

static void cg_list(Node *s)
{
    for (; s; s = s->next) cg_stmt(s);
}

/* ---------- functions and the whole program ---------- */
static void declare_function(Node *fn)
{
    int n = ast_count(fn->a), i = 0;
    LLVMTypeRef *ps = malloc((n ? n : 1) * sizeof *ps);
    LLVMTypeRef ft;
    char name[512];
    Node *p;
    for (p = fn->a; p; p = p->next) ps[i++] = p->ival ? ptrT : i64T;
    ft = LLVMFunctionType(i64T, ps, (unsigned)n, 0);
    snprintf(name, sizeof name, "f_%s", fn->name);
    fn->aux = LLVMAddFunction(mod, name, ft);
    free(ps);
}

static void define_function(Node *fn)
{
    int s, i = 0;
    Node *p;

    cur_fn = (LLVMValueRef)fn->aux;
    cur_node = fn;
    entry_bb = LLVMAppendBasicBlockInContext(ctx, cur_fn, "entry");
    LLVMPositionBuilderAtEnd(B, entry_bb);

    slots = calloc(fn->nslots ? fn->nslots : 1, sizeof *slots);
    for (s = 0; s < fn->nslots; s++)
        slots[s] = LLVMBuildAlloca(B, fn->slot_types[s] == T_ARR ? ptrT : i64T, fn->slot_names[s]);
    for (s = 0; s < fn->nslots; s++)
        LLVMBuildStore(B, fn->slot_types[s] == T_ARR ? g_empty : c64(0), slots[s]);
    for (p = fn->a; p; p = p->next, i++)
        LLVMBuildStore(B, LLVMGetParam(cur_fn, (unsigned)i), slots[i]);

    cg_list(fn->b->a);
    if (!terminated()) LLVMBuildRet(B, c64(0));      /* falling off the end returns 0 */
    free(slots);
}

static void cg_program(Node *prog)
{
    Node *f;
    LLVMTypeRef ps[3];
    LLVMValueRef m, call;
    LLVMBasicBlockRef bb;

    ctx = LLVMContextCreate();
    mod = LLVMModuleCreateWithNameInContext("arrow", ctx);
    LLVMSetTarget(mod, triple);                                      /* set before generating code so that */
    LLVMSetModuleDataLayout(mod, LLVMCreateTargetDataLayout(tm));    /* loads/stores get the right alignment */
    B = LLVMCreateBuilderInContext(ctx);
    i64T = LLVMInt64TypeInContext(ctx);
    i32T = LLVMInt32TypeInContext(ctx);
    i1T = LLVMInt1TypeInContext(ctx);
    ptrT = LLVMPointerTypeInContext(ctx, 0);
    voidT = LLVMVoidTypeInContext(ctx);
    invariant_kind = LLVMGetMDKindIDInContext(ctx, "invariant.load", 14);

    ps[0] = i64T; ps[1] = i64T; ps[2] = i64T;
    rt_oob  = declare_rt("arrow_oob", voidT, ps, 3, 1);
    rt_div  = declare_rt("arrow_div", i64T, ps, 3, 0);
    rt_mod  = declare_rt("arrow_mod", i64T, ps, 3, 0);
    rt_new  = declare_rt("arrow_new", ptrT, ps, 2, 0);
    rt_show = declare_rt("arrow_show", voidT, ps, 1, 0);
    rt_read = declare_rt("arrow_read", i64T, ps, 1, 0);
    g_empty = LLVMAddGlobal(mod, i64T, "arrow_empty");

    for (f = prog; f; f = f->next) declare_function(f);
    for (f = prog; f; f = f->next) define_function(f);

    /* int main(void) { f_main(); return 0; } */
    m = LLVMAddFunction(mod, "main", LLVMFunctionType(i32T, NULL, 0, 0));
    bb = LLVMAppendBasicBlockInContext(ctx, m, "entry");
    LLVMPositionBuilderAtEnd(B, bb);
    {
        LLVMValueRef fm = (LLVMValueRef)sema_main()->aux;
        call = LLVMBuildCall2(B, LLVMGlobalGetValueType(fm), fm, NULL, 0, "");
        (void)call;
    }
    LLVMBuildRet(B, LLVMConstInt(i32T, 0, 0));
}

/* ---------- back end: optimize, emit object code, link ---------- */
static int run_cmd(char *const argv[])
{
    pid_t pid = fork();
    int st;
    if (pid < 0) fatal("fork failed", NULL);
    if (pid == 0) { execvp(argv[0], argv); perror(argv[0]); _exit(127); }
    waitpid(pid, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : 1;
}

static const char *find_runtime(void)
{
    static char buf[4096];
    char exe[4096];
    ssize_t n;
    const char *env = getenv("ARROW_RT");
    if (env && access(env, R_OK) == 0) return env;
    n = readlink("/proc/self/exe", exe, sizeof exe - 1);
    if (n > 0) {
        exe[n] = 0;
        snprintf(buf, sizeof buf, "%s/build/arrow_rt.o", dirname(exe));
        if (access(buf, R_OK) == 0) return buf;
    }
    if (access(ARROW_RT_OBJ, R_OK) == 0) return ARROW_RT_OBJ;
    return NULL;
}

static void write_ir(const char *path)
{
    char *err = NULL;
    if (LLVMPrintModuleToFile(mod, path, &err)) fatal("cannot write IR file", err);
}

static void usage(FILE *out)
{
    fprintf(out,
        "Arrow compiler (Phase 2, ahead-of-time, LLVM back end)\n"
        "usage: arrowc [options] program.arw\n"
        "  -o FILE         name of the executable (default: program name without .arw)\n"
        "  -O0 -O1 -O2 -O3 LLVM optimization level (default -O2)\n"
        "  --emit-ir       write the LLVM IR as generated (before LLVM optimizes it) to FILE.ll and stop\n"
        "  -S              write the final LLVM IR (after optimization) to FILE.ll and stop\n"
        "  --no-bce        turn off the bounds-check elimination pass\n"
        "  --stats         print how many bounds checks were removed\n"
        "  -h, --help      show this help\n");
}

int main(int argc, char **argv)
{
    const char *path = NULL, *out = NULL;
    int opt = 2, emit_ir = 0, emit_s = 0, use_bce = 1, stats = 0, i;
    char outbuf[1024], objpath[1100], irpath[1100], *err = NULL;
    FILE *f;
    int total = 0, removed = 0;
    LLVMTargetRef target;
    LLVMCodeGenOptLevel cgl;

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) { usage(stdout); return 0; }
        else if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
        else if (!strcmp(argv[i], "-O0")) opt = 0;
        else if (!strcmp(argv[i], "-O1")) opt = 1;
        else if (!strcmp(argv[i], "-O2")) opt = 2;
        else if (!strcmp(argv[i], "-O3")) opt = 3;
        else if (!strcmp(argv[i], "--emit-ir")) emit_ir = 1;
        else if (!strcmp(argv[i], "-S")) emit_s = 1;
        else if (!strcmp(argv[i], "--no-bce")) use_bce = 0;
        else if (!strcmp(argv[i], "--stats")) stats = 1;
        else if (argv[i][0] == '-' && argv[i][1]) { fprintf(stderr, "arrowc: unknown option '%s'\n", argv[i]); usage(stderr); return 2; }
        else if (!path) path = argv[i];
        else { fprintf(stderr, "arrowc: more than one input file given\n"); return 2; }
    }
    if (!path) { usage(stderr); return 2; }

    f = fopen(path, "r");
    if (!f) { fprintf(stderr, "arrowc: cannot open '%s'\n", path); return 2; }
    arrow_file = path;
    yyin = f;
    yyparse();
    fclose(f);
    if (arrow_nerrors == 0) sema_check(program_root);
    if (arrow_nerrors > 0) {
        fprintf(stderr, "%d error(s); nothing was compiled.\n", arrow_nerrors);
        return 1;
    }

    if (!out) {                                    /* default output name: basename without extension */
        char tmp[1024], *base, *dot;
        snprintf(tmp, sizeof tmp, "%s", path);
        base = basename(tmp);
        snprintf(outbuf, sizeof outbuf, "%s", base);
        dot = strrchr(outbuf, '.');
        if (dot && dot != outbuf) *dot = 0;
        else strcat(outbuf, ".out");
        out = outbuf;
    }

    if (use_bce) total = bce_run(program_root, &removed);
    if (stats) {
        if (!use_bce) printf("bounds checks: bounds-check elimination is off\n");
        else printf("bounds checks: %d array accesses, %d checks eliminated, %d kept\n", total, removed, total - removed);
    }

    LLVMInitializeNativeTarget();
    LLVMInitializeNativeAsmPrinter();
    triple = LLVMGetDefaultTargetTriple();
    if (LLVMGetTargetFromTriple(triple, &target, &err)) fatal("no LLVM target for this machine", err);
    cgl = opt == 0 ? LLVMCodeGenLevelNone : opt == 1 ? LLVMCodeGenLevelLess : opt == 2 ? LLVMCodeGenLevelDefault : LLVMCodeGenLevelAggressive;
    tm = LLVMCreateTargetMachine(target, triple, "generic", "", cgl, LLVMRelocPIC, LLVMCodeModelDefault);

    cg_program(program_root);
    if (LLVMVerifyModule(mod, LLVMReturnStatusAction, &err)) fatal("the generated IR is invalid (compiler bug)", err);

    snprintf(irpath, sizeof irpath, "%s.ll", out);
    if (emit_ir) { write_ir(irpath); printf("wrote %s (unoptimized IR)\n", irpath); return 0; }

    if (opt > 0) {
        static const char *pipelines[] = { "", "default<O1>", "default<O2>", "default<O3>" };
        LLVMPassBuilderOptionsRef po = LLVMCreatePassBuilderOptions();
        LLVMErrorRef e = LLVMRunPasses(mod, pipelines[opt], tm, po);
        if (e) { char *m = LLVMGetErrorMessage(e); fatal("LLVM optimization failed", m); }
        LLVMDisposePassBuilderOptions(po);
    }
    if (emit_s) { write_ir(irpath); printf("wrote %s (IR after -O%d)\n", irpath, opt); return 0; }

    snprintf(objpath, sizeof objpath, "%s.o", out);
    if (LLVMTargetMachineEmitToFile(tm, mod, objpath, LLVMObjectFile, &err)) fatal("cannot emit object code", err);

    {
        const char *rt = find_runtime();
        char *link_argv[] = { "cc", objpath, (char *)rt, "-o", (char *)out, NULL };
        int rc;
        if (!rt) { remove(objpath); fatal("runtime library build/arrow_rt.o not found", "run 'make' first"); }
        rc = run_cmd(link_argv);
        remove(objpath);
        if (rc != 0) fatal("linking failed", "is a C compiler (cc) installed?");
    }
    printf("built %s\n", out);
    return 0;
}
