/* ast.h - syntax tree shared by the interpreter (Phase 1) and the compiler (Phase 2) */
#ifndef ARROW_AST_H
#define ARROW_AST_H

#include <stdio.h>

typedef enum { T_NONE = 0, T_INT, T_ARR } Type;

typedef enum {
    N_INT, N_VAR, N_INDEX, N_BIN, N_UN, N_CALL, N_READ, N_NEW, N_ARRLIT, N_LEN, /* expressions */
    N_ASSIGN, N_SHOW, N_LOOP, N_RANGE, N_WHEN, N_GIVE, N_EXPRSTMT, N_BLOCK,     /* statements  */
    N_FN, N_PARAM                                                                /* declarations */
} NodeKind;

typedef enum {
    OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD,
    OP_LT, OP_LE, OP_GT, OP_GE, OP_EQ, OP_NE,
    OP_AND, OP_OR, OP_NEG, OP_NOT
} Op;

typedef struct Node Node;
struct Node {
    NodeKind kind;
    int line;
    long ival;          /* N_INT: value;  N_PARAM: 1 if array parameter */
    int op;             /* N_BIN / N_UN: Op */
    char *name;         /* identifier name */
    Node *a, *b, *c;    /* children (meaning depends on kind, see ast.c) */
    Node *next;         /* next element of a list (statements, args, params, functions) */

    /* filled in by semantic analysis */
    Type type;          /* type of an expression */
    int slot;           /* variable slot (N_VAR, N_INDEX, N_RANGE) */
    Node *fn;           /* N_CALL: resolved callee */
    int nslots;         /* N_FN: number of variable slots */
    Type *slot_types;   /* N_FN: type of each slot */
    char **slot_names;  /* N_FN: name of each slot */

    /* filled in by the optimizer / code generator */
    int safe;           /* N_INDEX: bounds check proven unnecessary */
    void *aux;          /* code generator scratch (LLVM function value) */
};

/* error reporting shared by lexer, parser and semantic analysis */
extern int arrow_nerrors;
extern const char *arrow_file;
void arrow_error(int line, const char *fmt, ...);

Node *ast_new(NodeKind kind, int line);
Node *ast_append(Node *list, Node *item);   /* returns the head of the list */
int   ast_count(Node *list);
const char *op_text(int op);
void  ast_dump(FILE *out, Node *n, int indent);

#endif
