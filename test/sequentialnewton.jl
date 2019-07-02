
# Create solver
opts = ProjectedNewtonSolverOptions{Float64}()
solver = SequentialNewtonSolver(prob,opts)
NN = N*n + (N-1)*m

# Test update functions
dynamics_constraints!(prob, solver)
dynamics_jacobian!(prob, solver)
update_constraints!(prob, solver)
constraint_jacobian!(prob, solver)
active_set!(prob, solver)
cost_expansion!(prob, solver)
invert_hessian!(prob, solver)

# Init solvers
solver0 = ProjectedNewtonSolver(prob)
update!(prob, solver0)
solver = SequentialNewtonSolver(prob, opts)
update!(prob, solver)

# Compare KKT solves
δV0 = solveKKT(prob, solver0)
Hinv = inv(Diagonal(solver0.H))
Y,y = active_constraints(prob, solver0)
# λ0, λ0_ = solve_cholesky(prob, solver0, Qinv, Rinv, A, B, C, D)
r0 = y - Y*Hinv*solver0.g
λ0 = (Y*Hinv*Y')\r0


# Solve KKT system
solver0 = ProjectedNewtonSolver(prob, opts)
update!(prob, solver0)
δV0 = solveKKT(prob, solver0)
δV0[NN+1:end][solver0.a.duals] ≈ λ0

solver = SequentialNewtonSolver(prob, opts)
update!(prob, solver)
δx,δu,δλ = solveKKT(prob, solver)
δz = [[x;u] for (x,u) in zip(δx[1:N-1], δu)]
push!(δz,δx[N])
vcat(δz...) ≈ -δV0[1:NN]
vcat(δλ...) ≈ δV0[NN+1:end][solver0.a.duals]



# Test projection
active_constraints!(prob, solver, solver.r)
vcat(solver.r...) ≈ y
λ,λ_,r = solve_cholesky(prob, solver, solver.r)
vcat(λ...) ≈ (Y*Hinv*Y')\y

solver0 = ProjectedNewtonSolver(prob)
solver0.opts.feasibility_tolerance = 1e-10
update!(prob, solver0)
projection!(prob, solver0)
max_violation(solver0)

solver = SequentialNewtonSolver(prob, opts)
solver.opts.feasibility_tolerance = 1e-10
solver.opts.verbose = true
update!(prob, solver)
projection!(prob, solver)
max_violation(solver) - max_violation(solver0) < 1e-16


# Residual
residual!(prob, solver)


# Multiplier projection
solver0 = ProjectedNewtonSolver(prob)
update!(prob, solver0)
Y,y = active_constraints(prob, solver0)
λ0 = duals(solver0.V)[solver0.a.duals]
res0 = solver0.g + Y'λ0
-(Y*Y')\(Y*res0)


solver = SequentialNewtonSolver(prob, opts)
update!(prob, solver)
residual!(prob, solver)
z = [[x;u] for (x,u) in zip(solver.δx[1:N-1], solver.δu)]
push!(z,solver.δx[N])
vcat(z...) ≈ solver0.g + Y'λ0

jac_mult!(prob, solver, solver.δx, solver.δu, solver.r)
vcat(solver.r...) ≈ Y*(solver0.g + Y'λ0)

eyes = [I for k = 1:N]
δλ, = solve_cholesky(prob, solver, solver.r, eyes, eyes)
vcat(δλ...) ≈ (Y*Y')\(Y*(solver0.g+Y'λ0))


# Compare Multiplier Projection
νinit = [rand(n)*(k!=1) for k = 1:N]
solver0 = ProjectedNewtonSolver(prob)
copyto!.(solver0.V.ν, νinit)
update!(prob, solver0)
res0,δλ0 = multiplier_projection!(prob, solver0)
Y,y = active_constraints(prob, solver0)
duals(solver0.V)

solver = SequentialNewtonSolver(prob, opts)
copyto!(view(solver.V.λ,2:2:2N-1), νinit[2:end])
update!(prob, solver)
_,δλ = multiplier_projection!(prob, solver)
vcat(δλ...) ≈ -δλ0
vcat(solver.V.λ...)
vcat(solver.V.λ...) ≈ duals(solver0.V)

# Test full newton step
solver0 = ProjectedNewtonSolver(prob,opts)
update!(prob, solver0)
newton_step!(prob, solver0)

solver = SequentialNewtonSolver(prob, opts)
update!(prob, solver)
newton_step!(prob, solver)



# Test solve step by step
solver0 = ProjectedNewtonSolver(prob,opts)
V0 = solver0.V
solver = SequentialNewtonSolver(copy(prob),opts)
V = solver.V
verbose = solver.opts.verbose

# Initial stats
update!(prob, solver0)
J0 = cost(prob, V0)
res0 = norm(residual(prob, solver0))
viol0 = max_violation(solver0)

update!(prob, solver)
J = cost(prob, V)
residual!(prob, solver, V)
res = res_norm(prob, solver)
viol = max_violation(solver)
J0 ≈ J
res0 ≈  res
viol0 ≈ viol

# Projection
verbose ? println("\nProjection:") : nothing
projection!(prob, solver0)
update!(prob, solver0)
r0,δλ0 = multiplier_projection!(prob, solver0)
Y,y = active_constraints(prob, solver0)
λ = duals(V0)[solver0.a.duals]

projection!(prob, solver)
update!(prob, solver)
r,δλ = multiplier_projection!(prob, solver)

abs(sqrt(norm(solver.δx)^2 + norm(solver.δu)^2) - norm(solver0.g + Y'λ)) < 1e-16
abs(max_violation(solver0) - max_violation(solver)) < 1e-16
norm(y - vcat(solver.r...)) < 1e-15
r ≈ r0
δλ0 ≈ -vcat(δλ...)


# Solve KKT
J0 = cost(prob, V)
res0 = norm(residual(prob, solver0))
viol0 = max_violation(solver0)
δV0, = solveKKT_Shur(prob, solver0, inv(Diagonal(solver0.H)))
δV0_ = PrimalDual(δV0, n,m,num_constraints(prob),N)

J = cost(prob, V)
residual!(prob, solver)
res = res_norm(prob, solver)
viol = max_violation(solver)
δx,δu,δλ = solveKKT(prob, solver)
δV0_.X ≈ -δx
δV0_.U ≈ -δu
δV0_.Y[solver0.a.duals] ≈ vcat(δλ...)
abs(viol0 - viol) < 1e-16
J0 ≈ J
res0 ≈ res


# Line Search
verbose ? println("\nLine Search") : nothing
α = 1.0
s = 0.01

J0 = cost(prob, solver0.V)
update!(prob, solver0)
res0 = norm(residual(prob, solver0))
V0_ = solver0.V + α*δV0

J0 = cost(prob, solver.V)
update!(prob, solver, solver.V, false)
residual!(prob, solver)
res = res_norm(prob, solver)
V_ = copy(solver.V)

solver.V.X ≈ solver0.V.X
solver.V.U ≈ solver0.V.U
vcat(solver.V.λ...) ≈ solver0.V.Y
vcat(δλ...) ≈ δV0_.Y[solver0.a.duals]

copyto!.(V_.X, solver.V.X - δx)
copyto!.(V_.U, solver.V.U - δu)
copyto!.(V_.λ, solver.V.λ)
update_duals!(prob, solver, V_, α*δλ)


V0_.X ≈ X_
V0_.U ≈ U_
V0_.Y ≈ vcat(λ_...)

update!(prob, solver0, V0_)
Y,y = active_constraints(prob, solver0)
(Y*Y')\y
update!(prob, solver, V_)
active_constraints!(prob, solver, solver.r)
vcat(solver.r...)
y
_projection!(prob, solver)

vcat(solver.δλ...)
update!(prob, solver, V_)


projection!(prob, solver0, V0_)
projection!(prob, solver, V_)
norm(V0_.X - X_)
norm(V0_.U - U_)

res0, = multiplier_projection!(prob, solver0, V0_)
J0 = cost(prob, V0_)


res, = multiplier_projection!(prob, solver, V_)
J = cost(prob, V_)

V0_.Y
vcat(V_.λ...)


δV
vcat(V_.λ...) - V0_.Y
δλ


@btime res_norm($prob, $solver, $vals)
@btime norm([$vals.x; $vals.u])
@btime norm(residual($prob, $solver0))

jac_mult!(prob, solver, vals.λ, vals.x, vals.u)
solver.Qinv .* vals.x
solver.Rinv .* vals.u

V0 = PrimalDual(prob)
solver0.opts.verbose = false
solver.opts.verbose = false
@btime begin
    copyto!($solver0.V.V, $V0.V)
    projection!($prob, $solver0)
end
@btime begin
    copyto!($solver.V.V, $V0.V)
    projection!($prob, $solver, $vals)
end

solver0.Y.blocks
solver0.a.duals
solver0.Y.blocks[solver0.a.duals,:]
solver0.y.blocks[solver0.a.duals]

@btime projection!($prob, $solver, $vals)
@btime begin
    Y,y = active_constraints(prob, solver0)
    HinvY = $Hinv*Y'
    HinvY*((Y*HinvY)\y)
end
z = [[vals.x[k]; vals.u[k]] for k = 1:N-1]
push!(z,vals.x[N])
vcat(z...) ≈ Hinv*Y'*((Y*Hinv*Y')\y)


C = [solver.∇C[k][a[k],1:n] for k = 1:N]
D = [solver.∇C[k][a[k],4:5] for k = 1:N-1]
a = solver.active_set
part_z = (x=1:n,u=n+1:n+m)
ai = [collect(1:p) for p in num_constraints(prob)]
@btime C2 = [view($solver.∇C[k],$a[k],:) for k = 1:N]
for k = 1:N
    C2[k].indices[1] = findall(a[k])
end


struct KKTFactors{T}
    E::MatrixTrajectory{T}
    F::MatrixTrajectory{T}
    G::Vector{Cholesky{T,Matrix{T}}}
    K::MatrixTrajectory{T}
    L::MatrixTrajectory{T}
    M::MatrixTrajectory{T}
    H::Vector{Cholesky{T,Matrix{T}}}
    y_part::Vector{Int}
end

function KKTFactors(n::Int, m::Int, p::Vector{Int}, N::Int)
    E = [zeros(n,n) for p in p_active]
    F = [zeros(n,p) for p in p_active]
    G = [cholesky(Matrix(I,n,n)) for p in p_active]

    K = [zeros(p,n) for p in p_active]
    L = [zeros(p,p) for p in p_active]
    M = [zeros(p,n) for p in p_active]
    H = [cholesky(Matrix(I,p,p)) for p in p_active]

    y_part = ones(Int,2,N-1)*n
    y_part[2,:] = p[1:end-1]
    y_part = vec(y_part)
    insert!(y_part,1,3)
    push!(y_part, p[N])

    KKTFactors(E,F,G,K,L,M,H,y_part)
end

struct KKTJacobian{T}
    ∇F::Vector{PartedArray{T,2,Matrix{T},P}} where P
    ∇C::Vector{PartedArray{T,2,Matrix{T},P} where P}
    active_set::Vector{Vector{Bool}}
end

function KKTJacobian(prob::Problem)
    n,m,N = size(prob)
    part_f = create_partition2(prob.model)
    constraints = prob.constraints

    ∇F = [PartedMatrix(zeros(n,n+m+1),part_f) for k = 1:N]
    ∇C = [PartedMatrix(con,n,m) for con in constraints.C]
    ∇C[N] = PartedMatrix(constraints[N],n,m,:terminal)
    active_set = [ones(Bool,pk) for pk in p]

    KKTJacobian(∇F, ∇C, active_set)
end

function *(Y::KKTJacobian, r::AbstractVector{<:AbstractVector})
    N = length(Y.∇F)

    for k = 1:N
