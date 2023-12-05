package erasure

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

import "dependencies:cli" // https://github.com/GoNZooo/odin-cli

Erasure_Error :: union {
	Unable_To_Read_File,
	Parse_Error,
	mem.Allocator_Error,
}

Parse_Error :: struct {}

Unable_To_Read_File :: struct {
	filename: string,
	error:    os.Errno,
}

Command :: union {
	Encode,
	Decode,
}

Encode :: struct {
	N:     int `cli:"N,num-code"`,
	K:     int `cli:"K,num-data"`,
	w:     int `cli:"w,word-size"`,
	input: string `cli:"i,input/required"`,
	shard: string `cli:"s,shard/required"`,
}

Decode :: struct {
	N:      int `cli:"N,num-code"`,
	K:      int `cli:"K,num-data"`,
	w:      int `cli:"w,word-size"`,
	output: string `cli:"o,output/required"`,
	shard:  string `cli:"s,shard/required"`,
}

/*
    Usage: eraser [command] [options]
    
    Commands:
    
      encode              encode data
      decode              decode data
    
    General Options:
      -N                  code chunks in a block # default: 5
      -K                  data chunks in a block # default: 3
      -w                  bytes in a word in a chunks (u8|u16|u32|u64) # default: u64
    
      --file              name of data file: input for encoding and output for decoding
      --shard             prefix of code files: output for encoding and input for decoding
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

	usage :: `Usage: eraser [command] [options]
    
	    Commands:
    
	      encode              encode data
	      decode              decode data
    
	    General Options:
	      -N | --num-code     code chunks in a block # default: 5
	      -K | --num-data     data chunks in a block # default: 3
	      -w | --word-size    bytes in a word in a chunks (u8|u16|u32|u64) # default: u64
    
	      --input|output      name of data file: input for encoding and output for decoding
	      --shard             prefix of code files: output for encoding and input for decoding
	`

	arguments := os.args[1:]
	fmt.println("args =", arguments)

	if len(arguments) < 3 {
		fmt.println(usage)
		os.exit(1)
	}

	command, remaining_args, cli_error := cli.parse_arguments_as_type(
		arguments,
		Command,
	)
	defer delete(remaining_args)
	if cli_error != nil {
		fmt.eprintln("Failed to parse arguments:", cli_error)
		os.exit(1)
	}

	switch c in command {
	case Encode:
		encode(c)
	case Decode:
		decode(c)
	case:
		fmt.println(usage)
		os.exit(1)
	}

	// error := process_file(filename)
	// if error != nil {
	// fmt.eprintf("Error while processing file '%s': %v\n", filename, error)
	// os.exit(1)
	// }
}

encode :: proc(c: Encode) {
	fmt.printf("N=%d, K=%d, w=%d\n", c.N, c.K, c.w)
	fmt.printf("input=%s, shard=%s\n", c.input, c.shard)
}

decode :: proc(c: Decode) {
	fmt.printf("N=%d, K=%d, w=%d\n", c.N, c.K, c.w)
	fmt.printf("output=%s, shard=%s\n", c.output, c.shard)
}

process_file :: proc(filename: string) -> Erasure_Error {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)

	return nil
}
