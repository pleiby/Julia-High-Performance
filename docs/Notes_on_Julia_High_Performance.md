Getting System Information re Processors
-----------------------------------------

- Standard approach is julia `versioninfo()` function

        julia> versioninfo(verbose=true)

- shows physical and virtual cores and their utilization
- shows memory and amount free
- shows relevant environment variables
- Result example:

        julia> versioninfo(verbose=true)
        Julia Version 1.4.2
        Commit 44fa15b150* (2020-05-23 18:35 UTC)
        Platform Info:
        OS: macOS (x86_64-apple-darwin18.7.0)
        uname: Darwin 18.7.0 Darwin Kernel Version 18.7.0: Mon Apr 27 20:09:39 PDT 2020; root:xnu-4903.278.35~1/RELEASE_X86_64 x86_64 i386
        CPU: Intel(R) Core(TM) i5-8279U CPU @ 2.40GHz: 
                    speed         user         nice          sys         idle          irq
            #1  2400 MHz      48668 s          0 s      25597 s     358508 s          0 s
            #2  2400 MHz       2886 s          0 s       2101 s     427754 s          0 s
            #3  2400 MHz      42806 s          0 s      17305 s     372632 s          0 s
            #4  2400 MHz       2775 s          0 s       1796 s     428171 s          0 s
            #5  2400 MHz      36744 s          0 s      13805 s     382194 s          0 s
            #6  2400 MHz       2724 s          0 s       1618 s     428400 s          0 s
            #7  2400 MHz      28254 s          0 s       9794 s     394695 s          0 s
            #8  2400 MHz       2755 s          0 s       1467 s     428520 s          0 s
            
        Memory: 8.0 GB (921.734375 MB free)
        Uptime: 179930.0 sec
        Load Avg:  1.88818359375  2.22705078125  2.03857421875
        WORD_SIZE: 64
        LIBM: libopenlibm
        LLVM: libLLVM-8.0.1 (ORCJIT, skylake)
        Environment:
        JULIA_EDITOR = "/Users/paulleiby/Desktop/Visual Studio Code.app/Contents/Resources/app/bin/code"
        JULIA_NUM_THREADS = 
        XPC_FLAGS = 0x0
        HOME = /Users/paulleiby
        TERM = xterm-256color


#### Getting System/Hardward info from `Hwloc` Package

```julia
using Hwloc
Hwloc.num_physical_cores()
```

Threading (Sengupta 2019, Chap 9)
---------------------------------

### Starting threads
- The number of real threads that Julia can run is fixed at startup. 
- It depends on the JULIA_NUM_THREADS environmental variable and is checked when the Julia runtime starts up. 
- If the variable is not set, the default number of threads is 1
- To store a value for JULIA_NUM_THREADS

        $ export JULIA_NUM_THREADS = 4

- Or set the JULIA_NUM_THREADS environment variable at the terminal prompt:

        $ JULIA_NUM_THREADS=4 ./julia

- setting/resetting number of threads (JULIA_NUM_THREADS) from VS Code:
    - see settings of the Julia extension of vscode.
    - Shift-CMD-P (Invoke VS Code Command Palette): 
        - Preference: Open Settings (UI)
            - Select setting for User/Extensions/Julia 
                - Julia: Num Threads
                - specify desired number

- From Julia, can check the number of threads using the `Threads.nthreads` function.


```julia
using Base.Threads
nthreads()
```

#### @threads macro

```julia
a = [0, 0, 0, 0]

@threads for i in 1:nthreads()
              a[threadid()] = threadid()
end

a
## 4-element Array{Int64,1}:
##  1
##  2
##  3
##  4
```

#### Thread safety and synchronization primitives
- Threads imply code running simultaneously on multiple processor cores
- The processors and their code have access to the entire memory of the computer
- Risk is that code in two threads can attempt to change memory location at the same time, or out of sequence

Our first simple/naiive attempt, run the loop on multiple threads:

```julia
function sum_thread_base(x)
    r = zero(eltype(x))
    @threads for i in eachindex(x)
        @inbounds r += x[i]
    end
    return r
end
```

We can then compare this function against Julia's built-in sum as follows:

```julia
a=rand(10_000_000);
@btime sum($a)
##  6.746 ms (0 allocations: 0 bytes) (Sengupta 2019)
## 5.000462435093071e6
##  4.166 ms (0 allocations: 0 bytes) (MacPro, 4 threads, Julia V1.4)
## 5.000228696747844e6 (MacPro, 4 threads, Julia V1.4)
@btime sum_thread_base($a)
##  1.566 s (5506561 allocations: 84.01 MiB)  (Sengupta 2019)
## 1.250442324066673e6
##  258.169 ms (20000024 allocations: 305.18 MiB) (MacPro, 4 threads, Julia V1.4)
## 1.3178999821310753e6 (MacPro, 4 threads, Julia V1.4)
```

- Wrong answer: inside the loop, we are trying to read and write to r, the result variable. Doing that simultaneously in multiple threads leads to wrong values
- Slow: because ...

- One solution to unsafe access of sum variable `r`: create r as an atomic variable.
- Operations/adding to to r will be a single indivisible operation.
    - writing the result to r will be an operation that cannot be interrupted by any other thread
    - The atomic addition is performed by the `atomic_add!` method

```julia
function sum_thread_atomic(x)
    r = Atomic{eltype(x)}(zero(eltype(x)))
    @threads for i in eachindex(x)
        @inbounds atomic_add!(r, x[i])
    end
    return r[]
end

@btime sum_thread_atomic($a)
## 883.710 ms (2 allocations: 48 bytes) (Sengupta 2019)
## 5.000462435092813e6
## 466.441 ms (24 allocations: 2.73 KiB) (MacPro, 4 threads, Julia V1.4)
## 5.000228696748323e6 (MacPro, 4 threads, Julia V1.4)
```

- Correct
- Slow, because: atomic operations implies that only one thread (one CPU) can increment the sum at a time. As a result, the overall operation is significantly slower.
-  need to reduce the "contention" between threads
    - requires some complexity in the code

- a fast way with some complication, breaks the sum so that different accumulators are used for different threads:

```julia
function sum_thread_split(A)
    r = Atomic{eltype(A)}(zero(eltype(A))) # must use atomic  variables to avoid simultaneous or ill-timed access
    len, rem = divrem(length(A), nthreads())
    #Split the array equally among the threads
    @threads for t in 1:nthreads()
        r[] = zero(eltype(A))
        @simd for i in (1:len) .+ (t-1)*len # use this little speedup trick too vectorizing add
        @inbounds r[] += A[i] # inbounds also speed up, avoiding index bound check
        end
        atomic_add!(r, r[]) # atomic var r requires atomic_add!
    end
    result = r[]
    #process up the remaining data
    @simd for i in length(A)-rem+1:length(A)
        @inbounds result += A[i]
    end
    return result
end

@btime sum_thread_split($a) # prefix vars in macro with $ to delay evaluation
## 1.501 ms (2 allocations: 64 bytes) (Sengupta 2019)
## 5.000462435093066e6
## 11.064 ms (24 allocations: 2.75 KiB) (MacPro, 4 threads, Julia v1.4)
## 2.6282013329576096e6 (MacPro, 4 threads, Julia v1.4)
```

On macOS or Linux, the htop command shows us CPU usage

### Threaded libraries

- e.g. BLAS for matrix mult
```julia
a = rand(1000, 1000);
b = rand(1000, 1000);

@btime $a*$b;
## 34.593 ms (2 allocations: 7.63 MiB) (Sengupta 2019)
## 11.304 ms (2 allocations: 7.63 MiB) (MacPro, 4 CPUs)
```

### Over-subscription
- When using libraries that manage and maintain their own threads, it is important not to over-subscribe your threads. 
    - When total number of threads in the system outpaces machine capacity, performance will suffer.

```julia
function matmul_serial(x)
   first_num = zeros(length(x))
   for i in eachindex(x)
      @inbounds first_num[i] = (x[i]'*x[i])[1]
   end
   return first_num
end

function matmul_thread(x)
   first_num = zeros(length(x))
   @threads for i in eachindex(x)
      @inbounds first_num[i] = (x[i]'*x[i])[1]
   end
   return first_num
end
```

Time these functions for a set of 100 matrices. 
The threaded version is slower than the serial version.
This is due to over-subscription of the threads.

```julia
m = [rand(1000, 1000) for _ in 1:100];
@btime matmul_serial(m);
## 2.886 s (201 allocations: 762.95 MiB) (Sengupta 2019)
## 1.082 s (201 allocations: 762.95 MiB) (MacPro, 4 threads, Julia v1.4)

@btime matmul_thread(m);
## 4.082 s (202 allocations: 762.95 MiB) (Sengupta 2019)
## 1.358 s (225 allocations: 762.95 MiB) (MacPro, 4 threads, Julia v1.4)
```

To see the number of threads currently used by BLAS:

```julia
ccall((:openblas_get_num_threads64_, Base.libblas_name), Cint, ())
```

To set (reduce) the number of threads used by BLAS, 
and avoid over-subscription:

```julia
using LinearAlgebra
BLAS.set_num_threads(1)

@btime matmul_thread(m);
## 2.500 s (202 allocations: 762.95 MiB) (Sengupta 2019)
## 732.491 ms (224 allocations: 762.95 MiB) (MacPro, 4 threads, Julia v1.4)
```

### Summary
- use careful consideration when writing code with threads. 
    - First, ensure that the number of threads used is commensurate with the number of CPU cores. 
    - Second, be careful in accessing global state. 
    - And finally, be cognizant of any other threaded libraries 

----------------------------------------------------------------------


## Presentation of Composable Multi-threaded Parallelism in July 2019

- See [Announcing composable multi-threaded parallelism in Julia](https://julialang.org/blog/2019/07/multithreading/)
23 July 2019 | Jeff Bezanson (Julia Computing), Jameson Nash (Julia Computing), Kiran Pamnany (Intel)

- Now: Existing `@threads for` uses will still work, and now I/O is fully supported:

```julia
Threads.@threads for i = 1:10
    println("i = $i on thread $(Threads.threadid())")
end
## i = 7 on thread 3
## i = 4 on thread 2
## i = 9 on thread 4
## i = 5 on thread 2
## i = 10 on thread 4
## i = 6 on thread 2
## i = 8 on thread 3
## i = 1 on thread 1
## i = 2 on thread 1
## i = 3 on thread 1
```

- Any piece of a program can be marked for execution in parallel
- A "task" will be started to run that code automatically on an available thread.
- A dynamic scheduler handles all the decisions and details

```julia
import Base.Threads.@spawn

function fib(n::Int)
    if n < 2
        return n
    end
    t = @spawn fib(n - 2)
    return fib(n - 1) + fetch(t)
end
```

This, of course, is the classic highly-inefficient tree recursive implementation of the Fibonacci sequence — but running on any number of processor cores! The line t = @spawn fib(n - 2) starts a task to compute fib(n - 2), which runs in parallel with the following line computing fib(n - 1). fetch(t) waits for task t to complete and gets its return value.

Try some nested parallelism. A perennial favorite example is mergesort, which divides its input in half and recursively sorts each half. The halves can be sorted independently

```julia
import Base.Threads.@spawn

"""
    psort!(v, lo::Int=1, hi::Int=length(v))

sort the elements of `v` in place, from indices `lo` to `hi` inclusive
"""
function psort!(v, lo::Int=1, hi::Int=length(v))
    if lo >= hi                       # 1 or 0 elements; nothing to do
        return v
    end
    if hi - lo < 100000               # below some cutoff, run in serial
        sort!(view(v, lo:hi), alg = MergeSort)
        return v
    end

    mid = (lo+hi)>>>1                 # find the midpoint

    # here is where we use (recursive) thread-parallism
    half = @spawn psort!(v, lo, mid)  # task to sort the lower half; will run
    psort!(v, mid+1, hi)              # in parallel with the current call sorting
                                      # the upper half
                                      # wait simply waits for the specified task to finish:
    wait(half)                        # wait for the lower half to finish

    temp = v[lo:mid]                  # workspace for merging

    i, k, j = 1, lo, mid+1            # merge the two sorted sub-arrays
    @inbounds while k < j <= hi
        if v[j] < temp[i]
            v[k] = v[j]
            j += 1
        else
            v[k] = temp[i]
            i += 1
        end
        k += 1
    end
    @inbounds while k < j
        v[k] = temp[i]
        k += 1
        i += 1
    end

    return v
end
```

Now some simple test of this:

```julia
a = rand(20000000);

b = copy(a); @time sort!(b, alg = MergeSort);   # single-threaded, internal sort, same MergeSort alg
##  2.589243 seconds (11 allocations: 76.294 MiB, 0.17% gc time)
##  2.150737 seconds (103.12 k allocations: 81.510 MiB) (On MacPro, 4 threads in REPL)

b = copy(a); @time sort!(b, alg = MergeSort);
##  2.582697 seconds (11 allocations: 76.294 MiB, 2.25% gc time)
##  2.067265 seconds (3 allocations: 76.294 MiB) (On MacPro, 4 threads in REPL)

b = copy(a); @time psort!(b);    # two threads
##  1.770902 seconds (3.78 k allocations: 686.935 MiB, 4.25% gc time)
##  1.078564 seconds (334.56 k allocations: 702.872 MiB, 7.51% gc time) (On MacPro, 4 threads in REPL)

b = copy(a); @time psort!(b);
##  1.741141 seconds (3.78 k allocations: 686.935 MiB, 4.16% gc time)
##  0.934811 seconds (3.27 k allocations: 686.916 MiB, 8.08% gc time) (On MacPro, 4 threads in REPL)
```

We could run threaded-parallel MergeSort (`psort!`) on a with more CPU cores.
The results reported by Bezanson et al. 2019 are:

        $ for n in 1 2 4 8 16; do    JULIA_NUM_THREADS=$n ./julia psort.jl; done
        2.949212 seconds (3.58 k allocations: 686.932 MiB, 4.70% gc time)
        1.861985 seconds (3.77 k allocations: 686.935 MiB, 9.32% gc time)
        1.112285 seconds (3.78 k allocations: 686.935 MiB, 4.45% gc time)
        0.787816 seconds (3.80 k allocations: 686.935 MiB, 2.08% gc time)
        0.655762 seconds (3.79 k allocations: 686.935 MiB, 4.62% gc time)

Note the speedup is remarkable, but certainly sub-linear in the number of cores/threads.
How much of this is the threading overhead compared to task duration.
But the halving and threading stops at size 10^5, and the total size is 2 x 10^7.

Question: how large a "task" can be dispatched to a thread?

Here's what you need to know if you want to upgrade your code over this period.
