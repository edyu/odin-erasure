package erasure

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"

num_chosen :: proc(m: int, n: int) -> int {
	return math.factorial(m) / (math.factorial(n) * math.factorial(m - n))
}

choose :: proc(l: []int, k: int) -> (ret: [dynamic][dynamic]int) {
	assert(len(l) >= k)
	assert(k > 0)

	if (k == 1) {
		for i := 0; i < len(l); i += 1 {
			item: [dynamic]int = {l[i]}
			append(&ret, item)
		}
		return ret
	}

	c := choose(l[1:], k - 1)
	defer delete(c)
	defer for s in c do delete(s)

	for m in 0 ..< (len(l) - 1) {
		for n in 0 ..< len(c) {
			if (l[m] >= c[n][0]) do continue
			sub: [dynamic]int
			append(&sub, l[m])
			for j in 0 ..< len(c[n]) {
				append(&sub, c[n][j])
			}
			append(&ret, sub)
		}
	}
	return ret
}

@(test)
test_choose :: proc(t: ^testing.T) {
	c := choose([]int{1, 2, 3, 4, 5}, 2)
	testing.expect(
		t,
		len(c) == num_chosen(5, 2),
		fmt.tprintf(
			"expected: (5 choose 2)=%v, got %v",
			len(c),
			num_chosen(5, 2),
		),
	)
	c2 := choose([]int{0, 1, 2, 3, 4, 5}, 3)
	testing.expect(
		t,
		len(c2) == num_chosen(6, 3),
		fmt.tprintf(
			"expected: (6 choose 3)=%v, got %v",
			len(c2),
			num_chosen(6, 3),
		),
	)
}
