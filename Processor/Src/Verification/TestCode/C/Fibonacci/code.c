int Fibonacci ( int loop );

int Fibonacci ( int loop ) {
	int i, x, y, z;
	x = y = 1;
	for ( i = 0; i < loop; i++) {
		z = x + y;
		y = x;
		x = z;
	}
	return z;
}

int main() {
	int ret;
	ret = Fibonacci(20);
	return ret+1;
}
