package erasure

import "core:fmt"
import "core:io"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Erasure_Error :: union {
	Field_Error,
	Unable_To_Open_File,
	Argument_Parse_Error,
	mem.Allocator_Error,
	io.Error,
}

Argument_Parse_Error :: union {
	Missing_Argument,
	Wrong_Argument,
	Illegal_Argument,
}

Missing_Argument :: struct {
	field: string,
}

Wrong_Argument :: struct {
	field: string,
}

Illegal_Argument :: struct {
	reason: string,
}

Unable_To_Open_File :: struct {
	filename: string,
	errno:    os.Errno,
}

Sub_Command :: union {
	Encode,
	Decode,
}

Encode :: struct {}

Decode :: struct {}

Command :: struct {
	sub:  Sub_Command,
	N:    int,
	K:    int,
	w:    int,
	file: string,
	code: string,
}

/*
    Usage: erasure [command] [options]
    
    Commands:
    
      encode              encode data
      decode              decode data
    
    General Options:
      -N | --num-code     number of code chunks in a block; default: 5
      -K | --num-data     number of data chunks in a block; default: 3
      -w | --word-size    number of bytes in each word in a chunks (1|2|4|8); default: 8
    
      -f | --file         name of data file: input for encoding and output for decoding
      -c | --code         prefix of code files: output for encoding and input for decoding
*/
main :: proc() {
	context.logger = log.create_console_logger()
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintf(
				"=== %v allocations not freed: ===\n",
				len(track.allocation_map),
			)
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		if len(track.bad_free_array) > 0 {
			fmt.eprintf(
				"=== %v incorrect frees: ===\n",
				len(track.bad_free_array),
			)
			for entry in track.bad_free_array {
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&track)
	}

	usage :: `Usage: erasure [command] [options]
    
	    Commands:
    
	      encode              encode data
	      decode              decode data
    
	    General Options:
	      -N | --num-code     number of code chunks in a block; default: 5
	      -K | --num-data     number of data chunks in a block; default: 3
	      -w | --word-size    number of bytes in each word in a chunks (1|2|4|8); default: 8

	      -f | --file         name of data file: input for encoding and output for decoding
	      -c | --code         prefix of code files: output for encoding and input for decoding
	`

	arguments := os.args[1:]
	fmt.println("args =", arguments)

	if len(arguments) < 5 {
		fmt.println(usage)
		os.exit(1)
	}

	command, cli_error := parse_arguments(arguments)

	if cli_error != nil {
		fmt.eprintln("Failed to parse arguments:", cli_error)
		os.exit(1)
	}

	switch c in command.sub {
	case Encode:
		err := do_encode(command)
		if err != nil {
			fmt.eprintf("got error: %v\n", err)
			#partial switch e in err {
			case Unable_To_Open_File:
				if e.filename != command.file do defer delete(e.filename)
			}
		}
	case Decode:
		err := do_decode(command)
		if err != nil {
			fmt.eprintf("got error: %v\n", err)
			#partial switch e in err {
			case Unable_To_Open_File:
				if e.filename != command.file do defer delete(e.filename)
			}
		}
	case:
		fmt.println(usage)
		os.exit(1)
	}
}

parse_int_argument :: proc(
	arg: string,
) -> (
	value: int,
	error: Argument_Parse_Error,
) {
	v := strconv.atoi(arg)
	if v > 0 do return v, nil
	return 0, Wrong_Argument{field = arg}
}

parse_arguments :: proc(
	arguments: []string,
) -> (
	command: Command,
	error: Argument_Parse_Error,
) {
	command.N = 5
	command.K = 3
	command.w = 8

	switch arguments[0] {
	case "encode":
		command.sub = Encode{}
	case "decode":
		command.sub = Decode{}
	case:
		return command, Wrong_Argument{field = arguments[0]}
	}

	args := arguments[1:]

	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "-N", "--num-code":
			i += 1
			if i < len(args) {
				command.N = parse_int_argument(args[i]) or_return
			} else {
				return command, Missing_Argument{field = "num-code"}
			}
		case "-K", "--num-data":
			i += 1
			if i < len(args) {
				command.K = parse_int_argument(args[i]) or_return
			} else {
				return command, Missing_Argument{field = "num-data"}
			}
		case "-w", "--word-size":
			i += 1
			if i < len(args) {
				w := parse_int_argument(args[i]) or_return
				allowed: bit_set[1 ..= 8] = {1, 2, 4, 8}
				if w in allowed {
					command.w = w
				} else {
					return command, Wrong_Argument{field = args[i]}
				}
			} else {
				return command, Missing_Argument{field = "word-size"}
			}
		case "-f", "--file":
			i += 1
			if i < len(args) {
				command.file = args[i]
			} else {
				return command, Missing_Argument{field = "file"}
			}
		case "-c", "--code":
			i += 1
			if i < len(args) {
				command.code = args[i]
			} else {
				return command, Missing_Argument{field = "code"}
			}
		case:
			return command, Illegal_Argument{reason = args[i]}
		}
	}

	if command.N < command.K {
		return command, Illegal_Argument{reason = "1 <= K <= N"}
	}

	// if command.file == "" {
	// 	return command, Missing_Argument{field = "file"}
	// }
	if command.code == "" {
		return command, Missing_Argument{field = "code"}
	}

	return command, nil
}

do_encode :: proc(c: Command) -> (err: Erasure_Error) {
	fmt.printf("N=%d, K=%d, w=%d\n", c.N, c.K, c.w)
	fmt.printf("input=%s, shard=%s\n", c.file, c.code)
	handle: os.Handle
	if c.file == "" do handle = os.stdin
	else {
		errno: os.Errno
		handle, errno = os.open(c.file)
		if errno != os.ERROR_NONE {
			return Unable_To_Open_File{filename = c.file, errno = errno}
		}
	}
	defer os.close(handle)
	fmt.printf("opening input file %s\n", c.file)
	input := os.stream_from_handle(handle)

	output := make([]io.Writer, c.N)
	defer delete(output)
	for i in 0 ..< c.N {
		errno: os.Errno
		buf: [4]u8
		parts := []string{c.code, strconv.itoa(buf[:], i)}
		filename := strings.concatenate(parts)
		fmt.printf("opening shard file %s\n", filename)
		handle, errno = os.open(filename, os.O_WRONLY | os.O_CREATE)
		if errno != os.ERROR_NONE {
			return Unable_To_Open_File{filename = filename, errno = errno}
		}
		defer delete(filename)
		output[i] = os.stream_from_handle(handle)
	}

	fmt.println("initializing erasure coder")
	coder := init_erasure_coder(c.N, c.K, c.w) or_return
	switch coder.w {
	case 1:
		encode(coder, u8, input, output)
	case 2:
		encode(coder, u16be, input, output)
	case 4:
		encode(coder, u32be, input, output)
	case 8:
		fmt.println("encoding...")
		encode(coder, u64be, input, output)
		fmt.println("encoded")
	}
	return nil
}

do_decode :: proc(c: Command) -> (err: Erasure_Error) {
	fmt.printf("N=%d, K=%d, w=%d\n", c.N, c.K, c.w)
	fmt.printf("output=%s, shard=%s\n", c.file, c.code)

	handle: os.Handle
	if c.file == "" do handle = os.stdout
	else {
		errno: os.Errno
		handle, errno = os.open(c.file, os.O_WRONLY | os.O_CREATE)
		if errno != os.ERROR_NONE {
			return Unable_To_Open_File{filename = c.file, errno = errno}
		}
	}
	defer os.close(handle)
	output := os.stream_from_handle(handle)

	excluded := sample(c.N, c.N - c.K)
	defer delete(excluded)
	fmt.printf("excluding shards: %v\n", excluded)
	input := make([]io.Reader, c.K)
	defer delete(input)
	j: int
	for i in 0 ..< c.N {
		if slice.contains(excluded, i) do continue
		errno: os.Errno
		buf: [4]u8
		parts := []string{c.code, strconv.itoa(buf[:], i)}
		filename := strings.concatenate(parts)
		handle, errno = os.open(filename)
		if errno != os.ERROR_NONE {
			return Unable_To_Open_File{filename = filename, errno = errno}
		}
		defer delete(filename)
		input[j] = os.stream_from_handle(handle)
		j += 1
	}
	coder := init_erasure_coder(c.N, c.K, c.w) or_return
	switch coder.w {
	case 1:
		decode(coder, u8, excluded, input, output)
	case 2:
		decode(coder, u16be, excluded, input, output)
	case 4:
		decode(coder, u32be, excluded, input, output)
	case 8:
		decode(coder, u64be, excluded, input, output)
	}
	return nil
}

sample :: proc(max: int, num: int) -> (values: []int) {
	data := make([]int, max)
	defer delete(data)
	for i := 0; i < max; i += 1 {
		data[i] = i
	}
	values = make([]int, num)
	values[0] = rand.choice(data)
	for i := 1; i < num; i += 1 {
		for true {
			values[i] = rand.choice(data)
			if !slice.contains(values[0:i], values[i]) do break
		}
	}

	return
}
