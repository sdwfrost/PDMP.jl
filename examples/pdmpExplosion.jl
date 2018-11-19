using Revise, PDMP, LinearAlgebra, Random, DifferentialEquations
const r = 10.

function AnalyticalSample(xc0,xd0,ti,nj::Int64)
    xch = [xc0[1]]
    xdh = [xd0[1]]
    th  = [ti]
    t = ti
    while length(th)<nj
        xc = xch[end]
        xd = xdh[end]
        S = -log(rand())
        a = -r * (2mod(xd,2)-1)
        dt = log(a*S/xc+1)/a
        t += dt
        push!(th, t)
        push!(xch,xc + a * S )
        push!(xdh,xd .+ 1 )
        S = -log(rand())
    end
    return th,xch,xdh
end


function F!(ẋ, xc, xd, t, parms)
    ẋ[1] = -r * (2mod(xd[1],2)-1) * xc[1]
end

R(x) = x

function R!(rate, xc, xd, t, parms, sum_rate::Bool)
    # rate fonction
    if sum_rate==false
        rate[1] = R(xc[1])
        rate[2] = parms[1]
        return 0.
    else
        return R(xc[1]) + parms[1]
    end
end

xc0 = vec([1.0])
xd0 = vec([0,0])

nu = [[1 0];[0 -1]]
parms = vec([0.0])
tf = 100000.
nj = 50

# sampling of the PDMP
res = PDMP.pdmp!(xc0, xd0, F!, R!, nu, parms, 0.0, tf, n_jumps = 2,   ode = CVODE_BDF())

Random.seed!(8)
    res_a = AnalyticalSample(xc0,xd0,0.,nj)
println("\n\nComparison of solvers")
for ode in [:cvode,:lsoda,Tsit5(),AutoTsit5(Rosenbrock23())]
    Random.seed!(8)
    res =  PDMP.pdmp!(xc0, xd0, F!, R!, nu, parms, 0.0, tf, n_jumps = nj, ode = ode, verbose = false)
    println("--> norm difference = ", res.time - res_a[1] |> norm, "  - solver = ",ode)
end

# using Plots
plot(res.time,res.xc[1,:],label = "CHV",marker=:d)
# plot!(res_a[1],res_a[2])
# plot(res.time - res_a[1])
