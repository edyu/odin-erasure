# odin-erasure

Library for erasure coding using binary finite fields.
The code was originally based on [vishesh-khemani/erasure-coding](https://github.com/vishesh-khemani/erasure-coding).

To test it out on the command line:

1. Install task from [taskfile.dev](https://taskfile.dev)
2. `task run erasure encode [<options>] --file <input file> --code <code file prefix>`
3. `task run erasure decode [<options>] --file <output file> --code <code file prefix>`

The `options` are as follows:

      -N | --num-code     number of code chunks in a block; default 5
      -K | --num-data     number of data chunks in a block; default 3
      -w | --word-size    number of bytes in each word in a chunks (1|2|4|8); default: 8

Note that you have to make sure to use the same `<code file prefix>` for encode and decode operations.

The default options will specify a _3 of 5_ erasure coder *(N=5, K=3)*. In other words, it will spread the data into 5 chunks but only requires any 3 out of 5 chunks to reconstruct the data.

