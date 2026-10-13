extern short callee(short a);
short caller(short x) { return callee(x); }
