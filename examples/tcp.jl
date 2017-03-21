push!(LOAD_PATH, "/Users/rveltz/work/prog_gd/julia")
using PDMP

function F_tcp!(xcdot::Vector, xc::Vector, xd::Array{Int64}, t::Float64, parms::Vector{Float64})
  # vector field used for the continuous variable
  if mod(xd[1],2)==0
    xcdot[1] = xc[1]
  else
    xcdot[1] = -xc[1]
  end
  nothing
end

function F_tcp(xc::Vector, xd::Array{Int64}, t::Float64, parms::Vector{Float64})
  # vector field used for the continuous variable
  if mod(xd[1],2)==0
    return vec([xc[1]])
  else
    return vec([-xc[1]])
  end
end

function R_tcp(xc::Vector, xd::Array, t::Float64, parms::Vector, sum_rate::Bool)
  # rate fonction
  if sum_rate==false
    return vec([5.0/(1.0 + exp(-xc[1]/1.0 + 5.0)) + 0.1, parms[1]])
  else
    return 5.0/(1.0 + exp(-xc[1]/1.0 + 5.0)) + 0.1 + parms[1]
  end
end

xc0 = vec([0.05])
xd0 = vec([0, 1])

const nu_tcp = [[1 0];[0 -1]]
parms = vec([0.1]) # sampling rate
tf = 200.

srand(1234)
result =  PDMP.pdmp(2,        xc0,xd0,F_tcp,R_tcp,nu_tcp,parms,0.0,tf,false)
result =  @time PDMP.pdmp(200,xc0,xd0,F_tcp,R_tcp,nu_tcp,parms,0.0,tf,false)
# more efficient way, inplace modification
srand(1234)
result2=        PDMP.pdmp(2,xc0,xd0,F_tcp!,R_tcp,nu_tcp,parms,0.0,tf,false)
result2=  @time PDMP.pdmp(200,xc0,xd0,F_tcp!,R_tcp,nu_tcp,parms,0.0,tf,false)

println("--> Case optimised:")
srand(1234)
dummy_t =  PDMP.pdmp(2,xc0,xd0,F_tcp!,R_tcp,nu_tcp,parms,0.0,tf,false, algo=:chv_optim)
dummy_t =  @time PDMP.pdmp(200,xc0,xd0,F_tcp!,R_tcp,nu_tcp,parms,0.0,tf,false, algo=:chv_optim)

println("--> stopping time == tf? (not more) ",maximum(result.time) == tf)
println("#jumps = ", length(result.time))