#ifndef ARROW_SEMA_H
#define ARROW_SEMA_H
#include "ast.h"

/* Checks a whole program (a list of N_FN nodes) and annotates it with types,
   variable slots and resolved callees. Returns the number of errors found. */
int sema_check(Node *program);
Node *sema_main(void);   /* the 'main' function, valid after a successful check */

#endif
