############################################################################################
#                                  IMPLICIT METHODS 								       #
############################################################################################

function discrete_dynamics(::Type{RK3}, model::AbstractModel, x::SVector{N,T}, u::SVector{M,T},
		t, dt::T) where {N,M,T}
    k1 = dynamics(model, x,             u, t       )*dt;
    k2 = dynamics(model, x + k1/2,      u, t + dt/2)*dt;
    k3 = dynamics(model, x - k1 + 2*k2, u, t       )*dt;
    x + (k1 + 4*k2 + k3)/6
end

function discrete_dynamics(::Type{RK2}, model::AbstractModel, x::SVector, u::SVector, t, dt)
	k1 = dynamics(model, x,        u, t       )*dt
	k2 = dynamics(model, x + k1/2, u, t + dt/2)*dt
	x + k2
end

function discrete_dynamics(::Type{RK4}, model::AbstractModel, x::SVector, u::SVector, t, dt)
	k1 = dynamics(model, x,        u, t       )*dt
	k2 = dynamics(model, x + k1/2, u, t + dt/2)*dt
	k3 = dynamics(model, x + k2/2, u, t + dt/2)*dt
	k4 = dynamics(model, x + k3,   u, t + dt  )*dt
	x + (k1 + 4k2 + 4k3 + k4)/6
end


############################################################################################
#                                  EXPLICIT METHODS 								       #
############################################################################################

# Hermite Simpson
function evaluate!(vals::Vector{<:AbstractVector}, con::DynamicsConstraint{HermiteSimpson},
		Z::Traj, inds=1:length(Z)-1)
	N = length(Z)
	model = con.model
	fVal = con.fVal
	xMid = con.xMid

	for k = inds.start:inds.stop+1
		fVal[k] = dynamics(model, Z[k])
	end
	for k in inds
		xMid[k] = (state(Z[k]) + state(Z[k+1]))/2 + Z[k].dt/8 * (fVal[k] - fVal[k+1])
	end
	for k in inds
		Um = (control(Z[k]) + control(Z[k+1]))*0.5
		fValm = dynamics(model, xMid[k], Um)
		vals[k] = state(Z[k]) - state(Z[k+1]) + Z[k].dt*(fVal[k] + 4*fValm + fVal[k+1])/6
	end
end

function jacobian!(∇c::Vector{<:SizedMatrix}, con::DynamicsConstraint{HermiteSimpson,L,T,n},
		Z::Traj, inds=1:length(Z)-1) where {L,T,n}
	N = length(Z)
	model = con.model
	∇f = con.∇f
	xMid = con.xMid
	In = Diagonal(@SVector ones(n))

	xi = Z[1]._x
	ui = Z[1]._u

	# Compute dynamics Jacobian at each knot point
	for k = inds.start:inds.stop+1
		∇f[k] = jacobian(model, Z[k].z)
	end

	for k in inds
		Um = (control(Z[k]) + control(Z[k+1]))*0.5
		Fm = jacobian(model, [xMid[k]; Um])
		A1 = ∇f[k][xi,xi]
		B1 = ∇f[k][xi,ui]
		Am = Fm[xi,xi]
		Bm = Fm[xi,ui]
		A2 = ∇f[k+1][xi,xi]
		B2 = ∇f[k+1][xi,ui]
		dt = Z[k].dt
		A = dt/6*(A1 + 4Am*( dt/8*A1 + In/2)) + In
		B = dt/6*(B1 + 4Am*( dt/8*B1) + 2Bm)
		C = dt/6*(A2 + 4Am*(-dt/8*A2 + In/2)) - In
		D = dt/6*(B2 + 4Am*(-dt/8*B2) + 2Bm)
		∇c[k] = [A B C D]
	end
end

function cost(obj, dyn_con::DynamicsConstraint{HermiteSimpson}, Z)
	N = length(Z)
	model = dyn_con.model
    xMid = dyn_con.xMid
	fVal = dyn_con.fVal
	for k = 1:N
		fVal[k] = dynamics(model, Z[k])
	end
	for k = 1:N-1
		xMid[k] = (state(Z[k]) + state(Z[k+1]))/2 + Z[k].dt/8 * (fVal[k] - fVal[k+1])
	end
	J = 0.0
	for k = 1:N-1
		Um = (control(Z[k]) + control(Z[k+1]))*0.5
		J += Z[k].dt/6 * (stage_cost(obj[k], state(Z[k]), control(Z[k])) +
					    4*stage_cost(obj[k], xMid[k], Um) +
					      stage_cost(obj[k], state(Z[k+1]), control(Z[k+1])))
	end
	J += stage_cost(obj[N], state(Z[N]))
	return J
end

function cost_gradient!(E, obj, dyn_con::DynamicsConstraint{HermiteSimpson}, Z)
	N = length(Z)
	xi = Z[1]._x
	ui = Z[1]._u

	model = dyn_con.model
	fVal = dyn_con.fVal
	xMid = dyn_con.xMid
	∇f = dyn_con.∇f
	grad = dyn_con.grad

	for k = 1:N
		fVal[k] = dynamics(model, Z[k])
	end
	for k = 1:N-1
		xMid[k] = (state(Z[k]) + state(Z[k+1]))/2 + Z[k].dt/8 * (fVal[k] - fVal[k+1])
	end
	for k = 1:N
		∇f[k] = jacobian(model, Z[k])
		E[k].x .*= 0
		E[k].u .*= 0
	end

	for k in 1:N-1
		x1, u1 = state(Z[k]),   control(Z[k])
		x2, u2 = state(Z[k+1]), control(Z[k+1])
		xm, um = xMid[k], 0.5*(u1 + u2)
		Fm = jacobian(model, [xm; um])
		A1 = ∇f[k][xi,xi]
		B1 = ∇f[k][xi,ui]
		Am = Fm[xi,xi]
		Bm = Fm[xi,ui]
		A2 = ∇f[k+1][xi,xi]
		B2 = ∇f[k+1][xi,ui]
		dt = Z[k].dt

		gradient!(grad[1], obj[k], x1, u1)
		gradient!(grad[2], obj[k], x2, u2)
		gradient!(grad[3], obj[k], xm, um)

		∇x1,∇u1 = grad[1].x, grad[1].u #gradient(obj[k], x1, u1)
		∇x2,∇u2 = grad[2].x, grad[2].u #gradient(obj[k], x2, u2)
		∇xm,∇um = grad[3].x, grad[3].u #gradient(obj[k], xm, um)

		E[k].x   .+= dt/6 * (∇x1 + 4*( dt/8 * A1 + I/2)'∇xm)
		E[k].u   .+= dt/6 * (∇u1 + 4*( ( dt/8 * B1)'∇xm + 0.5I'*∇um))
		E[k+1].x .+= dt/6 * (∇x2 + 4*(-dt/8 * A2 + I/2)'∇xm)
		E[k+1].u .+= dt/6 * (∇u2 + 4*( (-dt/8 * B2)'∇xm + 0.5I'*∇um))
	end

	gradient!(grad[1], obj[N], state(Z[N]), control(Z[N]))
	E[N].x .+= grad[1].x #gradient(obj[N], state(Z[N]), control(Z[N]))[1]
	return nothing
end
