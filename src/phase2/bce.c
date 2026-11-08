/* bce.c - bounds-check elimination (own optimization pass, works on the syntax tree)
 *
 * The check for  a[idx]  can be dropped when we are inside a range loop
 *
 *        loop i in LO .. HI { ... a[i + c] ... }
 *
 * and all of the following hold:
 *   1. LO is a constant and LO + c >= 0                (so idx >= 0)
 *   2. HI is  len(a) - k  with a constant k >= 0 and c <= k   (so idx < len(a))
 *   3. the loop body never assigns a new array to the variable 'a'
 *      (the length of an array never changes, and 'i' cannot be assigned in the
 *       body - semantic analysis rejects that - so 'i' always lies in [LO, HI) )
 */
#include "bce.h"

typedef struct Loop { Node *range; struct Loop *outer; } Loop;

static int total, removed;

static int rebinds(Node *s, int slot)
{
    for (; s; s = s->next) {
        switch (s->kind) {
        case N_ASSIGN:
            if (s->b->kind == N_VAR && s->b->slot == slot) return 1;
            break;
        case N_LOOP:  if (rebinds(s->b->a, slot)) return 1; break;
        case N_RANGE: if (rebinds(s->c->a, slot)) return 1; break;
        case N_WHEN:
            if (rebinds(s->b->a, slot)) return 1;
            if (s->c && rebinds(s->c->a, slot)) return 1;
            break;
        case N_BLOCK: if (rebinds(s->a, slot)) return 1; break;
        default: break;
        }
    }
    return 0;
}

#define SMALL(c) ((c) > -(1L << 40) && (c) < (1L << 40))

/* idx has the form  i,  i + c,  c + i  or  i - c  for the loop variable in 'slot' */
static int affine(Node *idx, int slot, long *c)
{
    Node *l, *r;
    if (idx->kind == N_VAR && idx->slot == slot) { *c = 0; return 1; }
    if (idx->kind == N_BIN && (idx->op == OP_ADD || idx->op == OP_SUB)) {
        l = idx->a; r = idx->b;
        if (l->kind == N_VAR && l->slot == slot && r->kind == N_INT && SMALL(r->ival)) {
            *c = idx->op == OP_ADD ? r->ival : -r->ival;
            return 1;
        }
        if (idx->op == OP_ADD && r->kind == N_VAR && r->slot == slot && l->kind == N_INT && SMALL(l->ival)) {
            *c = l->ival;
            return 1;
        }
    }
    return 0;
}

/* hi has the form  len(a)  or  len(a) - k  (k >= 0 constant) */
static int len_minus(Node *hi, int arr_slot, long *k)
{
    Node *len = hi;
    *k = 0;
    if (hi->kind == N_BIN && hi->op == OP_SUB && hi->b->kind == N_INT && hi->b->ival >= 0 && SMALL(hi->b->ival)) {
        *k = hi->b->ival;
        len = hi->a;
    }
    return len->kind == N_LEN && len->a->kind == N_VAR && len->a->slot == arr_slot;
}

static int provable(Node *ix, Loop *ctx)
{
    Loop *l;
    for (l = ctx; l; l = l->outer) {
        Node *r = l->range;
        long c, k;
        if (!affine(ix->a, r->slot, &c)) continue;
        if (r->a->kind != N_INT || !SMALL(r->a->ival)) continue;
        if (r->a->ival + c < 0) continue;
        if (!len_minus(r->b, ix->slot, &k)) continue;
        if (c > k) continue;
        if (rebinds(r->c->a, ix->slot)) continue;
        return 1;
    }
    return 0;
}

static void walk_list(Node *s, Loop *ctx);

static void walk_expr(Node *e, Loop *ctx)
{
    Node *p;
    if (!e) return;
    switch (e->kind) {
    case N_INDEX:
        total++;
        if (provable(e, ctx)) { e->safe = 1; removed++; }
        walk_expr(e->a, ctx);
        break;
    case N_BIN:  walk_expr(e->a, ctx); walk_expr(e->b, ctx); break;
    case N_UN: case N_LEN: case N_NEW: walk_expr(e->a, ctx); break;
    case N_CALL: case N_ARRLIT:
        for (p = e->a; p; p = p->next) walk_expr(p, ctx);
        break;
    default: break;
    }
}

static void walk_stmt(Node *s, Loop *ctx)
{
    switch (s->kind) {
    case N_ASSIGN:
        walk_expr(s->a, ctx);
        walk_expr(s->b, ctx);            /* the target: N_VAR (ignored) or N_INDEX */
        break;
    case N_SHOW: case N_GIVE: case N_EXPRSTMT:
        walk_expr(s->a, ctx);
        break;
    case N_LOOP:
        walk_expr(s->a, ctx);
        walk_list(s->b->a, ctx);
        break;
    case N_RANGE: {
        Loop me;
        walk_expr(s->a, ctx);
        walk_expr(s->b, ctx);
        me.range = s;
        me.outer = ctx;
        walk_list(s->c->a, &me);
        break;
    }
    case N_WHEN:
        walk_expr(s->a, ctx);
        walk_list(s->b->a, ctx);
        if (s->c) walk_list(s->c->a, ctx);
        break;
    case N_BLOCK:
        walk_list(s->a, ctx);
        break;
    default: break;
    }
}

static void walk_list(Node *s, Loop *ctx)
{
    for (; s; s = s->next) walk_stmt(s, ctx);
}

int bce_run(Node *program, int *eliminated)
{
    Node *f;
    total = removed = 0;
    for (f = program; f; f = f->next) walk_list(f->b->a, NULL);
    *eliminated = removed;
    return total;
}
