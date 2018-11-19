###################################################################################################
###################################################################################################
###################################################################################################
### implementation of the CHV algo using DiffEq

# callable struct
function (prob::PDMPProblem)(u,t,integrator)
    (t == prob.sim.tstop_extended)
end

# The following function is a callback to discrete jump. Its role is to perform the jump on the solution given by the ODE solver
# callable struct
function (prob::PDMPProblem)(integrator)
	prob.verbose && printstyled(color=:green,"--> Jump detected!!, entry in callback\n")
	# find the next jump time
	t = integrator.u[end]
	prob.sim.lastjumptime = t

	# state of the continuous variable right before the jump

	# put the current continuous state variable in prob.xc
	@inbounds for ii in eachindex(prob.xc)
		prob.xc[ii] = integrator.u[ii]
	end

	prob.verbose && printstyled(color=:green,"--> jump not yet performed, xd = ",prob.xd,"\n")

	if (prob.save_pre_jump) && (t <= prob.tf)
		prob.verbose && printstyled(color=:green,"----> save pre-jump\n")
		push!(prob.Xc,integrator.u[1:end-1])
		push!(prob.Xd,copy(prob.xd))
		push!(prob.time,t)
	end

	# execute the jump
	prob.pdmpFunc.R(prob.rate,prob.xc,prob.xd,t,prob.parms, false)
	if (t < prob.tf)
		# Update event
		ev = pfsample(prob.rate,sum(prob.rate),length(prob.rate))

		deltaxd = view(prob.nu,ev,:)

		# Xd = Xd .+ deltaxd
		@inbounds for ii in eachindex(prob.xd)
			prob.xd[ii] += deltaxd[ii]
		end

		# Xc = Xc .+ deltaxc
		prob.pdmpFunc.Delta(prob.xc,prob.xd,t,prob.parms,ev)
	end
	prob.verbose && printstyled(color=:green,"--> jump effectued, xd = ",prob.xd,"\n")
	# we register the next time interval to solve ode
	prob.sim.njumps += 1
	prob.sim.tstop_extended -= log(rand())
	add_tstop!(integrator, prob.sim.tstop_extended)
	prob.verbose && printstyled(color=:green,"--> End jump\n\n")
end

# callable struct
function (prob::PDMPProblem{Tc,Td,vectype_xc,vectype_xd,Tnu,Tp,TF,TR,TD})(xdot::vectype_xc,x::vectype_xc,data,t::Tc) where {Tc,Td,vectype_xc<:AbstractVector{Tc},vectype_xd<:AbstractVector{Td},Tnu<:AbstractArray{Td},Tp,TF,TR,TD}
	# used for the exact method
	# we put [1] to use it in the case of the rejection method as well
	tau = x[end]
	sr = prob.pdmpFunc.R(prob.rate,x,prob.xd,tau,prob.parms,true)[1]
	# @assert(sr > 0.0, "Total rate must be positive")
	# isr = min(1.0e9,1.0 / sr)
	prob.pdmpFunc.F(xdot,x,prob.xd,tau,prob.parms)
	xdot[end] = 1.0
	@inbounds for i in eachindex(xdot)
		xdot[i] = xdot[i] / sr
	end
	nothing
end

function PDMPPb(xc0::vecc,xd0::vecd,
				F::TF,R::TR,DX::TD,
				nu::Tnu,parms::Tp,
				ti::Tc, tf::Tc,
				verbose::Bool = false;
				save_positions=(false,true)) where {Tc,Td,Tnu <: AbstractArray{Td}, Tp, TF ,TR ,TD, vecc <: AbstractVector{Tc}, vecd <:  AbstractVector{Td}}
	# custom type to collect all parameters in one structure
	return PDMPProblem{Tc,Td,typeof(xc0),typeof(xd0),Tnu,Tp,TF,TR,TD}(xc0,xd0,F,R,DX,nu,parms,ti,tf,save_positions[1],verbose)
end


"""
Implementation of the CHV method to sample a PDMP using the package `DifferentialEquations`. The advantage of doing so is to lower the number of calls to `solve` using an `integrator` method.
"""
function chv_diffeq!(xc0::vecc,xd0::vecd,
				F::TF,R::TR,DX::TD,
				nu::Tnu,parms::Tp,
				ti::Tc, tf::Tc,
				verbose::Bool = false;
				ode = Tsit5(),save_positions=(false,true),n_jumps::Int64 = Inf64, callback_algo = true) where {Tc,Td,Tnu <: AbstractArray{Td}, Tp, TF ,TR ,TD, vecc <: AbstractVector{Tc}, vecd <:  AbstractVector{Td}}

				# custom type to collect all parameters in one structure
				problem  = PDMPProblem{Tc,Td,typeof(xc0),typeof(xd0),Tnu,Tp,TF,TR,TD}(xc0,xd0,F,R,DX,nu,parms,ti,tf,save_positions[1],verbose)

	problem.verbose && printstyled(color=:red,"Entry in chv_diffeq\n")

	# vector to hold the state space for the extended system
# ISSUE FOR USING WITH STATIC-ARRAYS
	X_extended = similar(problem.xc,length(problem.xc)+1)
	X_extended[1:end-1] .= problem.xc
	X_extended[end] = ti	# definition of the callback structure passed to DiffEq

	cb = DiscreteCallback(problem, problem, save_positions = (false,false))

	# define the ODE flow, this leads to big memory saving
	# @show tf, problem.sim.tstop_extended
	prob_CHV = ODEProblem((xdot,x,data,tt)->problem(xdot,x,data,tt),X_extended,(0.0,tf))

	if callback_algo
		integrator = init(prob_CHV, ode, tstops = problem.sim.tstop_extended, callback=cb, save_everystep = false,reltol=1e-8,abstol=1e-8,advance_to_tstop=true,dt=0.0001)
	else
		integrator = init(prob_CHV, ode, tstops = problem.sim.tstop_extended, save_everystep = false,reltol=1e-8,abstol=1e-8,advance_to_tstop=true,dt=0.0001)
	end

	chv_diffeq!(problem,integrator,ti,tf;ode = ode, save_positions = save_positions,n_jumps = n_jumps, callback_algo = callback_algo)
end

function chv_diffeq!(problem::PDMPProblem{Tc,Td,vectype_xc,vectype_xd,Tnu,Tp,TF,TR,TD},
					integrator,ti::Tc,tf::Tc, verbose = false;ode=Tsit5(),
					save_positions=(false,true),n_jumps::Td = Inf64, callback_algo = true) where {Tc,Td,vectype_xc<:AbstractVector{Tc},vectype_xd<:AbstractVector{Td},Tnu<:AbstractArray{Td},Tp,TF,TR,TD}
	t = ti
	njumps = 0

	while (t < tf) && problem.sim.njumps < n_jumps-1
		problem.verbose && println("--> n = $(problem.sim.njumps), t = $t, δt = ",problem.sim.tstop_extended)
		step!(integrator)
		DiffEqBase.check_error!(integrator)
		if callback_algo == false
			problem(integrator) #this is to be used with no callback in the integrator, somehow this is 10x slower than the discrete callback solution
		end
		@assert( t < problem.sim.lastjumptime, "Could not compute next jump time $(problem.sim.njumps).\nReturn code = $(integrator.sol.retcode)\n $t < $(problem.sim.lastjumptime)")
		t = problem.sim.lastjumptime

		# the previous step was a jump!
		if njumps < problem.sim.njumps && save_positions[2] && (t <= problem.tf)
			problem.verbose && println("----> save post-jump, xd = ",problem.Xd)
			push!(problem.Xc,copy(problem.xc))
			# push!(problem.Xc,integrator.u[1:end-1])#copy(problem.xc))
			push!(problem.Xd,copy(problem.xd))
			push!(problem.time,t)
			njumps +=1
			problem.verbose && println("----> end save post-jump, ")
		end
	end
	problem.verbose && println("--> n = $(problem.sim.njumps), t = $t, t = ",integrator.u[end])
	# we check that the last bit [t_last_jump, tf] is not missing
	if t>tf
		problem.verbose && println("----> LAST BIT!!, xc = ",problem.Xc[end], ", xd = ",problem.xd)
		prob_last_bit = ODEProblem((xdot,x,data,tt)->problem.pdmpFunc.F(xdot,x,problem.xd,tt,problem.parms),
					problem.Xc[end],(problem.time[end],tf))
		sol = solve(prob_last_bit, ode)
		push!(problem.Xc,sol.u[end])
		push!(problem.Xd,copy(problem.xd))
		push!(problem.time,sol.t[end])
	end
	return PDMPResult(problem.time,problem.Xc,problem.Xd)#, problem
end
