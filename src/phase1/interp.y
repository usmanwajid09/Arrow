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
 *  PHASE 1 - THE INTERPRETER
 *
 *  No intermediate code is generated and no LLVM is used.  The Bison
 *  actions above build the syntax tree of the program; the C code below
 *  (still part of this Bison file) executes that tree directly.
 *
 *  Values: an integer is a C long.  An array is a pointer to a block of
 *  longs whose element 0 is the length and whose elements 1..n are the data.
 * ===================================================================== */

#include <stdarg.h>
#include <pthread.h>

typedef union { long i; long *a; } Slot;

static long empty_array[1] = { 0 };       /* shared by every array variable that was never assigned */
static int  call_depth = 0;
static int  max_depth = 100000;

typedef enum { X_NORMAL, X_RETURN } XStat;

static void rt_error(int line, const char *fmt, ...)
{
    va_list ap;
    fflush(stdout);
    fprintf(stderr, "arrow: runtime error (line %d): ", line);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

static long ev_int(Node *e, Slot *fr);
static long *ev_arr(Node *e, Slot *fr);
static XStat exec_list(Node *s, Slot *fr, long *ret);

static long wrap_add(long a, long b) { return (long)((unsigned long)a + (unsigned long)b); }
static long wrap_sub(long a, long b) { return (long)((unsigned long)a - (unsigned long)b); }
static long wrap_mul(long a, long b) { return (long)((unsigned long)a * (unsigned long)b); }

static long *elem_ptr(Node *ix, Slot *fr)
{
    long *arr = fr[ix->slot].a;
    long idx = ev_int(ix->a, fr);
    if ((unsigned long)idx >= (unsigned long)arr[0])
        rt_error(ix->line, "index %ld out of range for array of length %ld", idx, arr[0]);
    return &arr[idx + 1];
}

static long call_function(Node *call, Slot *fr)
{
    Node *fn = call->fn, *p, *arg;
    Slot *nf;
    long ret = 0;
    int i;

    if (++call_depth > max_depth)
        rt_error(call->line, "call depth limit (%d) exceeded - is the recursion infinite?", max_depth);

    nf = calloc(fn->nslots ? fn->nslots : 1, sizeof(Slot));
    if (!nf) rt_error(call->line, "out of memory");
    for (i = 0; i < fn->nslots; i++)
        if (fn->slot_types[i] == T_ARR) nf[i].a = empty_array;

    for (p = fn->a, arg = call->a, i = 0; p && arg; p = p->next, arg = arg->next, i++) {
        if (p->ival) nf[i].a = ev_arr(arg, fr);
        else         nf[i].i = ev_int(arg, fr);
    }
    exec_list(fn->b->a, nf, &ret);
    free(nf);
    call_depth--;
    return ret;
}

static long *ev_arr(Node *e, Slot *fr)
{
    long *arr;
    long n, i;
    Node *p;

    switch (e->kind) {
    case N_VAR:
        return fr[e->slot].a;
    case N_NEW:
        n = ev_int(e->a, fr);
        if (n < 0) rt_error(e->line, "new[%ld]: array size must not be negative", n);
        if (n > (1L << 40)) rt_error(e->line, "new[%ld]: array is too large", n);
        arr = calloc((size_t)n + 1, sizeof(long));
        if (!arr) rt_error(e->line, "new[%ld]: out of memory", n);
        arr[0] = n;
        return arr;
    case N_ARRLIT:
        n = ast_count(e->a);
        arr = calloc((size_t)n + 1, sizeof(long));
        if (!arr) rt_error(e->line, "out of memory");
        arr[0] = n;
        for (p = e->a, i = 1; p; p = p->next, i++) arr[i] = ev_int(p, fr);
        return arr;
    default:
        rt_error(e->line, "internal error: not an array expression");
        return NULL;
    }
}

static long ev_int(Node *e, Slot *fr)
{
    long a, b;

    switch (e->kind) {
    case N_INT:   return e->ival;
    case N_VAR:   return fr[e->slot].i;
    case N_INDEX: return *elem_ptr(e, fr);
    case N_LEN:   return ev_arr(e->a, fr)[0];
    case N_CALL:  return call_function(e, fr);
    case N_READ: {
        long v;
        if (scanf("%ld", &v) != 1) rt_error(e->line, "read(): end of input or not an integer");
        return v;
    }
    case N_UN:
        a = ev_int(e->a, fr);
        return e->op == OP_NEG ? wrap_sub(0, a) : (a == 0);
    case N_BIN:
        if (e->op == OP_AND) return ev_int(e->a, fr) != 0 && ev_int(e->b, fr) != 0;
        if (e->op == OP_OR)  return ev_int(e->a, fr) != 0 || ev_int(e->b, fr) != 0;
        a = ev_int(e->a, fr);
        b = ev_int(e->b, fr);
        switch (e->op) {
        case OP_ADD: return wrap_add(a, b);
        case OP_SUB: return wrap_sub(a, b);
        case OP_MUL: return wrap_mul(a, b);
        case OP_DIV:
            if (b == 0) rt_error(e->line, "division by zero");
            return b == -1 ? wrap_sub(0, a) : a / b;
        case OP_MOD:
            if (b == 0) rt_error(e->line, "remainder by zero");
            return b == -1 ? 0 : a % b;
        case OP_LT: return a < b;
        case OP_LE: return a <= b;
        case OP_GT: return a > b;
        case OP_GE: return a >= b;
        case OP_EQ: return a == b;
        case OP_NE: return a != b;
        default: break;
        }
        break;
    default:
        break;
    }
    rt_error(e->line, "internal error: bad expression");
    return 0;
}

static XStat exec_stmt(Node *s, Slot *fr, long *ret)
{
    switch (s->kind) {
    case N_ASSIGN: {
        Node *lv = s->b;
        if (lv->kind == N_VAR) {
            if (lv->type == T_ARR) fr[lv->slot].a = ev_arr(s->a, fr);
            else                   fr[lv->slot].i = ev_int(s->a, fr);
        } else {
            long v = ev_int(s->a, fr);          /* value first, then the index */
            *elem_ptr(lv, fr) = v;
        }
        return X_NORMAL;
    }
    case N_SHOW:
        printf("%ld\n", ev_int(s->a, fr));
        return X_NORMAL;
    case N_LOOP:
        while (ev_int(s->a, fr) != 0)
            if (exec_list(s->b->a, fr, ret) == X_RETURN) return X_RETURN;
        return X_NORMAL;
    case N_RANGE: {
        long lo = ev_int(s->a, fr), hi = ev_int(s->b, fr), c;
        for (c = lo; c < hi; c++) {
            fr[s->slot].i = c;
            if (exec_list(s->c->a, fr, ret) == X_RETURN) return X_RETURN;
            if (c == hi - 1) break;
        }
        return X_NORMAL;
    }
    case N_WHEN:
        if (ev_int(s->a, fr) != 0) return exec_list(s->b->a, fr, ret);
        if (s->c) return exec_list(s->c->a, fr, ret);
        return X_NORMAL;
    case N_GIVE:
        *ret = ev_int(s->a, fr);
        return X_RETURN;
    case N_EXPRSTMT:
        ev_int(s->a, fr);
        return X_NORMAL;
    case N_BLOCK:
        return exec_list(s->a, fr, ret);
    default:
        rt_error(s->line, "internal error: bad statement");
        return X_NORMAL;
    }
}

static XStat exec_list(Node *s, Slot *fr, long *ret)
{
    for (; s; s = s->next)
        if (exec_stmt(s, fr, ret) == X_RETURN) return X_RETURN;
    return X_NORMAL;
}

static void *run_main(void *arg)
{
    Node *call = ast_new(N_CALL, 0);
    (void)arg;
    call->fn = sema_main();
    call->name = "main";
    call_function(call, NULL);
    return NULL;
}

static void usage(FILE *out)
{
    fprintf(out,
        "Arrow interpreter (Phase 1)\n"
        "usage: arrow-interp [options] program.arw\n"
        "  --check    parse and check the program, but do not run it\n"
        "  --ast      print the syntax tree and exit\n"
        "  -h, --help show this help\n"
        "Input for read() is taken from standard input.\n");
}

int main(int argc, char **argv)
{
    const char *path = NULL;
    int check_only = 0, dump_ast = 0, i;
    FILE *f;

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) { usage(stdout); return 0; }
        else if (!strcmp(argv[i], "--check")) check_only = 1;
        else if (!strcmp(argv[i], "--ast")) dump_ast = 1;
        else if (argv[i][0] == '-' && argv[i][1]) { fprintf(stderr, "arrow-interp: unknown option '%s'\n", argv[i]); usage(stderr); return 2; }
        else if (!path) path = argv[i];
        else { fprintf(stderr, "arrow-interp: more than one input file given\n"); return 2; }
    }
    if (!path) { usage(stderr); return 2; }

    f = fopen(path, "r");
    if (!f) { fprintf(stderr, "arrow-interp: cannot open '%s'\n", path); return 2; }
    arrow_file = path;
    yyin = f;
    yyparse();
    fclose(f);
    if (arrow_nerrors == 0) sema_check(program_root);
    if (arrow_nerrors > 0) {
        fprintf(stderr, "%d error(s); the program was not run.\n", arrow_nerrors);
        return 1;
    }
    if (dump_ast) { ast_dump(stdout, program_root, 0); return 0; }
    if (check_only) { printf("%s: OK\n", path); return 0; }

    {   /* run on a thread with a large stack so deep (but finite) recursion works */
        pthread_t th;
        pthread_attr_t at;
        pthread_attr_init(&at);
        pthread_attr_setstacksize(&at, (size_t)512 << 20);
        if (pthread_create(&th, &at, run_main, NULL) == 0) {
            pthread_join(th, NULL);
        } else {
            max_depth = 5000;                 /* could not get a big stack: be conservative */
            run_main(NULL);
        }
    }
    fflush(stdout);
    return 0;
}
