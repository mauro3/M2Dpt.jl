using Printf
using M2Dpt
using LinearAlgebra

include("physics.jl")
include("numerics.jl")

# Pre-processing
const dampx = 1*(1-Vdamp/nx) # velocity damping for x-momentum equation
const dampy = 1*(1-Vdamp/ny) # velocity damping for y-momentum equation
const mpow  = -(1-1/n)/2     # exponent for strain rate dependent viscosity

"""
    expand!(Vexp, V, dims)
   
expand array using BC's - Free slip

"""
function expand!( Vexp::Array{Float64,2}, V::Array{Float64,2}, dims::Int64 )

    if dims == 1
        Vexp[:,2:end-1] .= V
        Vexp[:,1]       .= @view V[:,2]
        Vexp[:,end]     .= @view V[:,end-1]
    else
        Vexp[2:end-1,:] .= V
        Vexp[1,:]       .= @view V[2,:]
        Vexp[end,:]     .= @view V[end-1,:]
    end

end

function solve( m :: Mesh, f :: Fields )

    time   = 0.0
    dx, dy = mesh.dx, mesh.dy

    dtT = tetT*1/4.1*min(dx,dy)^2 # explicit timestep for 2D diffusion
    
    errs  = Float64[]

    Vx_exp = zeros(Float64,(nx+1,ny+2))
    Vy_exp = zeros(Float64,(nx+2,ny+1))
    etav   = zeros(Float64,(nx+1,ny+1)) 

    for it = 1:nt # Physical timesteps

        To    = f.T  # temperature from previous step (for backward-Euler integration)
        @show time += dtT # update physical time

        for iter = 1:niter # Pseudo-Transient cycles

    #        err   = [Vx(:); Vy(:); P(:); T(:); etac(:)];

            # used for damping x momentum residuals
            f.dVxdtauVx0 .= f.dVxdtauVx .+ dampx .* f.dVxdtauVx0  
            # used for damping y momentum residuals
            f.dVydtauVy0 .= f.dVydtauVy .+ dampy .* f.dVydtauVy0 
            #  Kinematics
            expand!(Vx_exp, f.Vx, 1)  
            expand!(Vy_exp, f.Vy, 2)

            divV = diff(f.Vx,dims=1)/dx .+ diff(f.Vy,dims=2)/dy
            Exxc = diff(f.Vx,dims=1)/dx .- 1/2*divV
            Eyyc = diff(f.Vy,dims=2)/dy .- 1/2*divV

            Exyv = 0.5*(diff(Vx_exp,dims=2)/dy 
                      + diff(Vy_exp,dims=1)/dx)

  @views    Exyc = 0.25*(Exyv[1:end-1,1:end-1] .+ 
                         Exyv[2:end,1:end-1]   .+ 
                         Exyv[1:end-1,2:end]   .+ 
                         Exyv[2:end,2:end])

            Eii2 = 0.5*(Exxc.^2 + Eyyc.^2) + Exyc.^2 # strain rate invariant

            # ------ Rheology
            # physical viscosity
            etac_phys = Eii2.^mpow.*exp.( -f.T.*(1 ./ (1 .+ f.T./T0)) ) 
            # numerical shear viscosity
            f.etac .= exp.(rel*log.(etac_phys) .+ (1-rel)*log.(f.etac)) 

            # expand viscosity fom cell centroids to vertices

  @views    etav[2:end-1,2:end-1] .= 0.25*(f.etac[1:end-1,1:end-1] 
                                         + f.etac[2:end,2:end] 
                                         + f.etac[1:end-1,2:end] 
                                         + f.etac[2:end,1:end-1])

            etav[:      ,[1 end]] .= etav[:        ,[2 end-1]]
            etav[[1 end],:      ] .= etav[[2 end-1],:        ]

            # ------ Pseudo-Time steps

            dtauP   = tetp*  4.1/min(nx,ny)*f.etac*(1.0+eta_b)

            dtauVx  = tetv*1/4.1*(min(dx,dy)^2 ./( 0.5*(f.etac[2:end,:] 
                      + f.etac[1:end-1,:]) ))/(1+eta_b)

            dtauVy  = tetv*1/4.1*(min(dx,dy)^2 ./( 0.5*(f.etac[:,2:end] 
                      + f.etac[:,1:end-1]) ))/(1+eta_b)

            dtauT   = tetT*1/4.1*min(dx,dy)^2

            # ------ Fluxes

            f.qx[2:end-1,:] = -diff(f.T,dims=1)/dx
            f.qy[:,2:end-1] = -diff(f.T,dims=2)/dy

            Sxx = -f.P .+ 2 * f.etac.*(Exxc .+ eta_b*divV)
            Syy = -f.P .+ 2 * f.etac.*(Eyyc .+ eta_b*divV)

            Txy = 2*etav.*Exyv
            Hs  = 4*f.etac.*Eii2

            # ------ Residuals

            f.dVxdtauVx .= diff(Txy[2:end-1,:],dims=2)/dy + diff(Sxx,dims=1)/dx
            f.dVydtauVy .= diff(Txy[:,2:end-1],dims=1)/dx + diff(Syy,dims=2)/dy

            dPdtauP     = - divV
            dTdtauT     = (To-f.T)/dtT - (diff(f.qx,dims=1)/dx 
                                       + diff(f.qy,dims=2)/dy) + Hs
            # ------ Updates

            # update with damping
            f.Vx[2:end-1,:] .+= dtauVx .* (f.dVxdtauVx .+ dampx.*f.dVxdtauVx0) 
            f.Vy[:,2:end-1] .+= dtauVy .* (f.dVydtauVy .+ dampy.*f.dVydtauVy0)
            f.P             .+= dtauP  .* dPdtauP
            f.T             .+= dtauT  .* dTdtauT

            if (iter % nout ==0) # Check

                fu     = hcat(f.dVxdtauVx, transpose(f.dVydtauVy))
                err_fu = norm(fu)/length(fu) 
                err_fp = norm(dPdtauP)/length(dPdtauP)
                err_fT = norm(dTdtauT)/length(dTdtauT)
                err    = [err_fu, err_fp, err_fT]

                if err_fu < epsi
                    push!(errs, err_fu)
                    break
                end

               @printf(" iter  = %d    \n", iter)
               @printf(" f_{u} = %1.3e \n", err_fu)
               @printf(" f_{p} = %1.3e \n", err_fp)
               @printf(" f_{T} = %1.3e \n", err_fT)

            end

        end


    end

    errs

end

mesh = Mesh( Lx, nx, Ly, ny)

fields = Fields( mesh, Vbc, r, Tamp )


@time solve( mesh, fields )

