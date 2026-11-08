/* sema.c - semantic analysis: scoped symbol tables, type checking, call resolution */
#include "sema.h"
#include <stdlib.h>
#include <string.h>

#define HSIZE 64

/* ---------- hash table helpers ---------- */
static unsigned hash(const char *s)
{
    unsigned h = 5381;
    while (*s) h = h * 33 + (unsigned char)*s++;
    return h % HSIZE;
}

typedef struct Sym {
    char *name;
    Type type;
    int slot;
    int loop_depth;          /* > 0 while we are inside a range loop that uses this variable */
    struct Sym *next;
} Sym;

typedef struct {
    Sym *tab[HSIZE];
    int nslots, cap;
    Type *types;
    char **names;
} Scope;

static Sym *lookup(Scope *sc, const char *name)
{
    Sym *s;
    for (s = sc->tab[hash(name)]; s; s = s->next)
        if (strcmp(s->name, name) == 0) return s;
    return NULL;
}

static Sym *declare(Scope *sc, const char *name, Type t)
{
    Sym *s = calloc(1, sizeof *s);
    unsigned h = hash(name);
    s->name = strdup(name);
    s->type = t;
    s->slot = sc->nslots++;
    s->next = sc->tab[h];
    sc->tab[h] = s;
    if (sc->nslots > sc->cap) {
        sc->cap = sc->cap ? sc->cap * 2 : 16;
        sc->types = realloc(sc->types, sc->cap * sizeof(Type));
        sc->names = realloc(sc->names, sc->cap * sizeof(char *));
    }
    sc->types[s->slot] = t;
    sc->names[s->slot] = s->name;
    return s;
}

/* ---------- function table ---------- */
typedef struct FEnt { char *name; Node *fn; struct FEnt *next; } FEnt;
static FEnt *ftab[HSIZE];
static Node *main_fn;

static Node *find_fn(const char *name)
{
    FEnt *e;
    for (e = ftab[hash(name)]; e; e = e->next)
        if (strcmp(e->name, name) == 0) return e->fn;
    return NULL;
}

Node *sema_main(void) { return main_fn; }

static const char *tname(Type t) { return t == T_ARR ? "array" : "integer"; }

/* ---------- expressions ---------- */
static Type ex(Scope *sc, Node *n);

static void want(Type got, Type need, int line, const char *what)
{
    if (got == T_NONE) return;               /* an error was already reported */
    if (got != need)
        arrow_error(line, "%s must be %s, but it is %s", what, tname(need), tname(got));
}

static Type ex(Scope *sc, Node *n)
{
    Type t = T_INT;
    Sym *s;
    Node *p, *q;

    switch (n->kind) {
    case N_INT:
        t = T_INT;
        break;
    case N_VAR:
        s = lookup(sc, n->name);
        if (!s) {
            arrow_error(n->line, "variable '%s' is used before it is assigned (use  value => %s;  first)", n->name, n->name);
            t = T_NONE;
        } else {
            n->slot = s->slot;
            t = s->type;
        }
        break;
    case N_INDEX:
        s = lookup(sc, n->name);
        want(ex(sc, n->a), T_INT, n->line, "array index");
        if (!s) {
            arrow_error(n->line, "array '%s' is used before it is assigned", n->name);
        } else if (s->type != T_ARR) {
            arrow_error(n->line, "'%s' is an integer, not an array; it cannot be indexed", n->name);
        } else {
            n->slot = s->slot;
        }
        t = T_INT;
        break;
    case N_BIN: {
        char what[64];
        snprintf(what, sizeof what, "left operand of '%s'", op_text(n->op));
        want(ex(sc, n->a), T_INT, n->line, what);
        snprintf(what, sizeof what, "right operand of '%s'", op_text(n->op));
        want(ex(sc, n->b), T_INT, n->line, what);
        t = T_INT;
        break;
    }
    case N_UN: {
        char what[64];
        snprintf(what, sizeof what, "operand of '%s'", op_text(n->op));
        want(ex(sc, n->a), T_INT, n->line, what);
        t = T_INT;
        break;
    }
    case N_CALL: {
        Node *fn = find_fn(n->name);
        int na = ast_count(n->a), i;
        if (!fn) {
            arrow_error(n->line, "call to undefined function '%s'", n->name);
            for (p = n->a; p; p = p->next) ex(sc, p);
        } else {
            n->fn = fn;
            if (na != ast_count(fn->a))
                arrow_error(n->line, "function '%s' takes %d argument(s) but %d given", n->name, ast_count(fn->a), na);
            for (p = n->a, q = fn->a, i = 1; p; p = p->next, i++) {
                Type at = ex(sc, p);
                if (q) {
                    Type pt = q->ival ? T_ARR : T_INT;
                    if (at != T_NONE && at != pt) {
                        arrow_error(p->line, "argument %d of '%s' must be %s, but it is %s",
                                    i, n->name, tname(pt), tname(at));
                    }
                    q = q->next;
                }
            }
        }
        t = T_INT;
        break;
    }
    case N_READ:
        t = T_INT;
        break;
    case N_NEW:
        want(ex(sc, n->a), T_INT, n->line, "array size in new[...]");
        t = T_ARR;
        break;
    case N_ARRLIT:
        for (p = n->a; p; p = p->next) want(ex(sc, p), T_INT, p->line, "array element");
        t = T_ARR;
        break;
    case N_LEN:
        want(ex(sc, n->a), T_ARR, n->line, "argument of len()");
        t = T_INT;
        break;
    default:
        t = T_NONE;
        break;
    }
    n->type = t;
    return t;
}

/* ---------- statements ---------- */
static void stmts(Scope *sc, Node *s);

static void stmt(Scope *sc, Node *n)
{
    Sym *s;
    Type rt;

    switch (n->kind) {
    case N_ASSIGN: {
        Node *lv = n->b;
        rt = ex(sc, n->a);                       /* the right-hand side is evaluated first */
        if (lv->kind == N_VAR) {
            s = lookup(sc, lv->name);
            if (!s) {
                s = declare(sc, lv->name, rt == T_NONE ? T_INT : rt);
            } else if (rt != T_NONE && s->type != rt) {
                arrow_error(n->line, "variable '%s' holds %s, so an %s value cannot flow into it",
                            lv->name, tname(s->type), tname(rt));
            }
            if (s->loop_depth > 0)
                arrow_error(n->line, "cannot assign to loop variable '%s' inside its own loop", lv->name);
            lv->slot = s->slot;
            lv->type = s->type;
        } else {                                  /* N_INDEX */
            want(rt, T_INT, n->line, "value stored into an array element");
            want(ex(sc, lv->a), T_INT, n->line, "array index");
            s = lookup(sc, lv->name);
            if (!s) arrow_error(n->line, "array '%s' is used before it is assigned", lv->name);
            else if (s->type != T_ARR) arrow_error(n->line, "'%s' is an integer, not an array; it cannot be indexed", lv->name);
            else lv->slot = s->slot;
            lv->type = T_INT;
        }
        break;
    }
    case N_SHOW:
        want(ex(sc, n->a), T_INT, n->line, "value given to show");
        break;
    case N_LOOP:
        want(ex(sc, n->a), T_INT, n->line, "loop condition");
        stmts(sc, n->b->a);
        break;
    case N_RANGE:
        want(ex(sc, n->a), T_INT, n->line, "range start");
        want(ex(sc, n->b), T_INT, n->line, "range end");
        s = lookup(sc, n->name);
        if (!s) s = declare(sc, n->name, T_INT);
        if (s->type != T_INT)
            arrow_error(n->line, "loop variable '%s' is an array, it must be an integer", n->name);
        if (s->loop_depth > 0)
            arrow_error(n->line, "loop variable '%s' is already used by an enclosing loop", n->name);
        n->slot = s->slot;
        s->loop_depth++;
        stmts(sc, n->c->a);
        s->loop_depth--;
        break;
    case N_WHEN:
        want(ex(sc, n->a), T_INT, n->line, "condition of when");
        stmts(sc, n->b->a);
        if (n->c) stmts(sc, n->c->a);
        break;
    case N_GIVE:
        want(ex(sc, n->a), T_INT, n->line, "returned value");
        break;
    case N_EXPRSTMT:
        ex(sc, n->a);
        break;
    case N_BLOCK:
        stmts(sc, n->a);
        break;
    default:
        break;
    }
}

static void stmts(Scope *sc, Node *s)
{
    for (; s; s = s->next) stmt(sc, s);
}

static void check_fn(Node *fn)
{
    Scope sc;
    Node *p;
    memset(&sc, 0, sizeof sc);
    for (p = fn->a; p; p = p->next) {
        if (lookup(&sc, p->name))
            arrow_error(p->line, "duplicate parameter '%s' in function '%s'", p->name, fn->name);
        declare(&sc, p->name, p->ival ? T_ARR : T_INT);
    }
    stmts(&sc, fn->b->a);
    fn->nslots = sc.nslots;
    fn->slot_types = sc.types;
    fn->slot_names = sc.names;
}

int sema_check(Node *prog)
{
    int before = arrow_nerrors;
    Node *f;
    unsigned h;

    for (f = prog; f; f = f->next) {
        if (find_fn(f->name)) {
            arrow_error(f->line, "function '%s' is defined more than once", f->name);
        } else {
            FEnt *e = calloc(1, sizeof *e);
            h = hash(f->name);
            e->name = f->name;
            e->fn = f;
            e->next = ftab[h];
            ftab[h] = e;
        }
    }
    main_fn = find_fn("main");
    if (!main_fn) arrow_error(0, "the program has no 'main' function");
    else if (main_fn->a) arrow_error(main_fn->line, "'main' must not take parameters");

    for (f = prog; f; f = f->next) check_fn(f);
    return arrow_nerrors - before;
}
