package main

import (
	"bufio"
	"bytes"
	"fmt"
	"math"
	"os"
	"runtime"
	"time"
)

const writerBufSize = 64 * 1024 * 1024 // 64 MiB

func main() {
	if len(os.Args) != 4 {
		fmt.Println("Uso: ./dicgen2 <num_cifras> <num_letras> <pos_inicio>")
		fmt.Println("Ejemplo: ./dicgen2 8 2 0   -> 2 letras desde pos 0")
		return
	}

	var n, nLetters, pos int
	if _, err := fmt.Sscan(os.Args[1], &n); err != nil || n < 1 {
		fmt.Println("num_cifras inválido")
		return
	}
	if _, err := fmt.Sscan(os.Args[2], &nLetters); err != nil || nLetters < 1 || nLetters > n {
		fmt.Println("num_letras inválido")
		return
	}
	if _, err := fmt.Sscan(os.Args[3], &pos); err != nil || pos < 0 || pos+nLetters > n {
		fmt.Println("pos_inicio inválido")
		return
	}

	letters := make([]byte, 0, 52)
	for c := byte('A'); c <= 'Z'; c++ {
		letters = append(letters, c)
	}
	for c := byte('a'); c <= 'z'; c++ {
		letters = append(letters, c)
	}

	totalLetters := math.Pow(float64(len(letters)), float64(nLetters))
	totalDigits := math.Pow(9, float64(n-nLetters))
	total := int64(totalLetters * totalDigits)
	sizeGB := float64(total*int64(n+1)) / (1024 * 1024 * 1024)
	timeEst := sizeGB / 0.5 // 500 MB/s
	fmt.Printf("Total combinaciones: %d\nTamaño estimado: %.2f GB\nTiempo estimado: %.1f s\n", total, sizeGB, timeEst)
	fmt.Print("¿Continuar? [y/N]: ")
	var resp string
	fmt.Scanln(&resp)
	if resp != "y" && resp != "Y" {
		fmt.Println("Cancelado.")
		return
	}

	name := fmt.Sprintf("dic_%dL%dP%d.txt", n, nLetters, pos)
	f, err := os.Create(name)
	if err != nil {
		panic(err)
	}
	defer f.Close()
	bw := bufio.NewWriterSize(f, writerBufSize)
	defer bw.Flush()

	runtime.GOMAXPROCS(runtime.NumCPU())

	line := make([]byte, n+1)
	line[n] = '\n'
	letIdx := make([]int, nLetters)
	digits := make([]byte, n-nLetters)
	for i := range digits {
		digits[i] = '1'
	}

	var written int64
	start := time.Now()
	for {
		copy(line, digitsToLine(digits, n, nLetters, pos, letters, letIdx))
		bw.Write(line)
		written++

		// Incrementar dígitos
		if incDigits(digits) {
			// reiniciar y aumentar letras
			for i := range digits {
				digits[i] = '1'
			}
			if incLetters(letIdx, len(letters)) {
				break
			}
		}

		if written%10000000 == 0 {
			bw.Flush()
			fmt.Printf("\r%.2f%%", float64(written)*100/float64(total))
		}
	}
	bw.Flush()
	fmt.Printf("\nHecho: %s en %v\n", name, time.Since(start))
}

func digitsToLine(digits []byte, n, nLetters, pos int, letters []byte, letIdx []int) []byte {
	out := bytes.Repeat([]byte{'1'}, n)
	copy(out[pos:pos+nLetters], mapLetters(letters, letIdx))
	j := 0
	for i := 0; i < n; i++ {
		if i < pos || i >= pos+nLetters {
			out[i] = digits[j]
			j++
		}
	}
	return out
}

func mapLetters(letters []byte, idx []int) []byte {
	r := make([]byte, len(idx))
	for i := range idx {
		r[i] = letters[idx[i]]
	}
	return r
}

func incDigits(digits []byte) bool {
	for i := len(digits) - 1; i >= 0; i-- {
		if digits[i] < '9' {
			digits[i]++
			return false
		}
		digits[i] = '1'
	}
	return true
}

func incLetters(idx []int, max int) bool {
	for i := len(idx) - 1; i >= 0; i-- {
		if idx[i] < max-1 {
			idx[i]++
			return false
		}
		idx[i] = 0
	}
	return true
}
