using BenchmarkTools


# ## Starting a Cluster

procs()

# change to 2 if started julia with -p2
addprocs(4)

procs()

# addprocs(["10.0.2.1", "10.0.2.2"]) ;

# ## Communication between Julia processes

a = remotecall(sqrt, 2, 4.0)

wait(a)

fetch(a)

remotecall_fetch(sqrt, 2, 4.0)


# # Programming parallel tasks

using Pkg
Pkg.add("Distributions")
using Distributions  # precompile

@everywhere using Distributions

@everywhere println(rand(Normal()))

# ## @spawn macro

a=@spawn randn(5,5)^2

fetch(a)

b=rand(5,5)

a=@spawn b^2

fetch(a)


@time begin
   A = rand(1000,1000)
   Bref = @spawn A^2
   fetch(Bref)
end;

@time begin
   Bref = @spawn rand(1000,1000)^2
   fetch(Bref)
end;

# ## @spawnat

r = remotecall(rand, 2, 2, 2)

s = @spawnat 3 1 .+ fetch(r)

fetch(s)



# ## @parallel for

function serial_add()
    s=0.0
    for i = 1:1000000
         s=s+randn()
    end
    return s
end

function parallel_add()
    return @distributed (+) for i=1:1000000
       randn()
    end
end

@btime serial_add()

@btime parallel_add()

# ## Parallel map

x=[rand(100,100) for i in 1:10];

@everywhere using LinearAlgebra

@btime map(svd, x);

@btime pmap(svd, x);


# ## Distributed Monte Carlo

@everywhere function darts_in_circle(N)
    n = 0
    for i in 1:N
        if rand()^2 + rand()^2 < 1
            n += 1
        end
    end
    return n
end

function distributed_pi(N, loops)
    n = sum(pmap((x)->darts_in_circle(N), 1:loops))
    4 * n / (loops * N)
end


@btime distributed_pi(1_000_000, 50)

julia> @btime serial_pi(50_000_000)

# ## Distributed Arrays

using Pkg
Pkg.add("DistributedArrays")
using DistributedArrays
@everywhere using DistributedArrays
d=dzeros(12, 12)
x=rand(10,10);
dx = distribute(x)

@everywhere function par(I)
    d=(size(I[1], 1), size(I[2], 1))
    m = fill(myid(), d)
    return m
end


m = DArray(par, (800, 800))

d.indices

r = @spawnat 2 localpart(d)


fetch(r)


@distributed (+) for i in 1:nworkers()
           sum(localpart(m))
       end

# ### Game of Life


function life_step(d::DArray)
   DArray(size(d),procs(d)) do I
      top = mod1(first(I[1])-1,size(d,1))  #outside edge
      bot = mod1( last(I[1])+1,size(d,1))
      left = mod1(first(I[2])-1,size(d,2))
      right = mod1( last(I[2])+1,size(d,2))
      old = Array{Bool}(undef, length(I[1])+2, length(I[2])+2) #temp array
      old[1 , 1 ] = d[top , left]  #get from remote
      old[2:end-1, 1 ] = d[I[1], left] # left
      old[end , 1 ] = d[bot , left]
      old[1 , end ] = d[top , right]
      old[2:end-1, end ] = d[I[1], right] # right
      old[end , end ] = d[bot , right]
      old[1 , 2:end-1] = d[top , I[2]] # top
      old[end , 2:end-1] = d[bot , I[2]] # bottom
      old[2:end-1, 2:end-1] = d[I[1], I[2]] # middle (local)

      life_rule(old) # Step!
   end
end

@everywhere function life_rule(old)
    m, n = size(old)
    new = similar(old, m-2, n-2)
    for j = 2:n-1
        @inbounds for i = 2:m-1
            nc = (+)(old[i-1,j-1], old[i-1,j], old[i-1,j+1],
                     old[i ,j-1], old[i ,j+1],
                     old[i+1,j-1], old[i+1,j], old[i+1,j+1])
            new[i-1,j-1] = (nc == 3 || nc == 2 && old[i,j])
        end
    end
    new
end


 A = DArray(I->rand(Bool, length.(I)), (20,20))

using Pkg; Pkg.add("Colors")
using Colors
 Gray.(A)

 B = Copy(A)
 B = Gray.(life_step(B))