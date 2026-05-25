package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"runtime"
	"time"
)

const (
	writerBufSize = 64 * 1024 * 1024 // 64 MiB
)

func main() {
	if len(os.Args) != 2 {
		fmt.Println("Uso: ./dicgen <num_cifras> (ejemplo: ./dicgen 9)")
		return
	}

	var n int
	_, err := fmt.Sscan(os.Args[1], &n)
	if err != nil || n < 1 || n > 18 {
		fmt.Println("Error: ingrese un número de cifras válido (1–18)")
		return
	}

	total := int64(math.Pow(9, float64(n)))
	lineSize := n + 1 // '\n'
	totalBytes := float64(total*int64(lineSize)) / (1024 * 1024 * 1024)
	estTime := totalBytes / 0.5 // SSD 500 MB/s = 0.5 GB/s
	fmt.Printf("Cifras: %d\nCombinaciones: %d\nTamaño estimado: %.2f GB\nTiempo estimado: %.1f s (≈ %.1f min)\n",
		n, total, totalBytes, estTime, estTime/60)
	fmt.Print("¿Continuar? [y/N]: ")

	var resp string
	fmt.Scanln(&resp)
	if resp != "y" && resp != "Y" {
		fmt.Println("Cancelado.")
		return
	}

	filename := fmt.Sprintf("dic_%d.txt", n)
	f, err := os.Create(filename)
	if err != nil {
		panic(err)
	}
	defer f.Close()
	bw := bufio.NewWriterSize(f, writerBufSize)

	start := time.Now()
	runtime.GOMAXPROCS(runtime.NumCPU())

	line := make([]byte, n+1)
	line[n] = '\n'

	// Inicializar contador a '1'
	counter := make([]byte, n)
	for i := range counter {
		counter[i] = '1'
	}

	var written int64
	for {
		copy(line, counter)
		bw.Write(line)
		written++
		// Incrementar contador base-9 ('1'..'9')
		i := n - 1
		for i >= 0 {
			if counter[i] < '9' {
				counter[i]++
				break
			}
			counter[i] = '1'
			i--
		}
		if i < 0 {
			break
		}
		if written%10000000 == 0 {
			bw.Flush()
			fmt.Printf("\r%.2f%%", float64(written)*100/float64(total))
		}
	}
	bw.Flush()
	fmt.Printf("\nHecho. Archivo: %s\nDuración: %v\n", filename, time.Since(start))
}
