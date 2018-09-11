### Solver options ###
opts = SolverOptions()
opts.square_root = false
opts.verbose=false
opts.cache=true
# opts.c1=1e-4
# opts.c2=2.0
# opts.mu_al_update = 10.0
opts.eps_constraint = 1e-5
opts.τ = 0.5
# opts.eps = 1e-6
# opts.iterations_outerloop = 250
# opts.iterations = 1000
######################


### Pendulum ###
n = 2 # number of pendulum states
m = 1 # number of pendulum controls
model! = Model(Dynamics.pendulum_dynamics!,n,m) # inplace dynamics model

## Unconstrained
obj_uncon = Dynamics.pendulum[2]
obj_uncon.R[:] = [1e-2]
solver_uncon = Solver(model!,obj_uncon,dt=0.1,opts=opts)

# -Initial state and control trajectories
X_interp = line_trajectory(solver_uncon.obj.x0,solver_uncon.obj.xf,solver_uncon.N)
U = ones(solver_uncon.model.m,solver_uncon.N)

results, stats = solve(solver_uncon,X_interp,U)

idx = find(x->x==2,results.iter_type) # get index for infeasible -> feasible solve switch

# if opts.verbose
#     plot(results.X',title="Pendulum (Infeasible start with unconstrained control and states (inplace dynamics))",ylabel="x(t)")
#     plot(results.U',title="Pendulum (Infeasible start with unconstrained control and states (inplace dynamics))",ylabel="u(t)")
#
#     plot(results.result[idx[1]-1].U',color="green")
#     plot!(results.result[idx[1]].U',color="blue")
#     plot!(results.result[end].U',color="red")
#
#     # Confirm visually that control output from infeasible start is a good warm start for constrained solve
#     tmp = ConstrainedResults(solver_uncon.model.n,solver_uncon.model.m,size(results.result[1].C,1),solver_uncon.N)
#     tmp.U[:,:] = results.result[idx[1]-1].U[1,:]
#     tmp2 = ConstrainedResults(solver_uncon.model.n,solver_uncon.model.m,size(results.result[1].C,1),solver_uncon.N)
#     tmp2.U[:,:] = results.result[end].U
#
#     rollout!(tmp,solver_uncon)
#     rollout!(tmp2,solver_uncon)
#
#     plot(tmp.X')
#     plot!(tmp2.X')
# end

# Test that infeasible control output is good warm start for dynamically constrained solve
@test norm(results.result[idx[1]-1].U[1,:]-vec(results.result[idx[1]+1].U)) < 1.0

# Test final state from foh solve
@test norm(results.X[:,end] - solver_uncon.obj.xf) < 1e-3


## Constraints
u_min = -2
u_max = 2
x_min = [-10;-10]
x_max = [10; 10]
obj_uncon = Dynamics.pendulum[2]
obj_uncon.R[:] = [1e-2]
obj = ConstrainedObjective(obj_uncon, u_min=u_min, u_max=u_max, x_min=x_min, x_max=x_max)

solver = Solver(model!,obj,dt=0.1,opts=opts)

# Linear interpolation for state trajectory
X_interp = line_trajectory(solver.obj.x0,solver.obj.xf,solver.N)
U = ones(solver.model.m,solver.N)

results, = solve(solver,X_interp,U)

idx = find(x->x==2,results.iter_type)

# if opts.verbose
#     plot(results.X',title="Pendulum (Infeasible start with constrained control and states (inplace dynamics))",ylabel="x(t)")
#     plot(results.U',title="Pendulum (Infeasible start with constrained control and states (inplace dynamics))",ylabel="u(t)")
#     println(results.X[:,end])
#
#     # trajectory_animation(results,filename="infeasible_start_state.gif",fps=5)
#     # trajectory_animation(results,traj="control",filename="infeasible_start_control.gif",fps=5)
#
#     plot(results.result[idx[1]-1].U',color="green")
#     plot(results.result[idx[1]+1].U',color="blue")
#     plot!(results.result[end].U',color="red")
# end

# Test final state from foh solve
@test norm(results.X[:,end] - solver.obj.xf) < 1e-3

# Test that control output from infeasible start is a good warm start for constrained solve
@test norm(results.result[idx[1]-1].U[1,:]-vec(results.result[idx[1]+1].U)) < 1.0

# if opts.verbose
#     # Check control outputs at important solve iterations
#     tmp = ConstrainedResults(solver.model.n,solver.model.m,size(results.result[1].C,1),solver.N)
#     tmp.U[:,:] = results.result[idx[1]-1].U[1,:]
#     tmp2 = ConstrainedResults(solver.model.n,solver.model.m,size(results.result[1].C,1),solver.N)
#     tmp2.U[:,:] = results.result[end].U
#
#     rollout!(tmp,solver)
#     plot(tmp.X')
#
#     rollout!(tmp2,solver)
#     plot!(tmp2.X')
# end
