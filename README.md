# Handwritten Assembly

For learning purposes only. Not practicality. Do not use in production.

Written for use with NASM.


## find_ip

Looks up IP address of domains.
Pass domain names on command line.
Does not use C Runtime

Location: src/win64/find_ip

## Threaded Collatz sequence

Demonstration of computing the Collatz sequence using
threaded "forth-like" code. There is no "live compilation"
of new words here though.

- `src/win64/itc_collatz.asm`: Indirect-threaded
- `src/win64/itc_collatz_reg.asm`: Indirect-threaded with top-of-stack in register
- `src/win64/dtc_collatz_reg.asm`: Direct-threaded with top-of-stack in register
