using LinearAlgebra

struct Fields

    Vx         ::  Array{Float64,2}
    Vy         ::  Array{Float64,2}
    T          ::  Array{Float64,2}
    P          ::  Array{Float64,2}
    etac       ::  Array{Float64,2}
    qx         ::  Array{Float64,2}
    qy         ::  Array{Float64,2}
    dVxdtauVx  ::  Array{Float64,2}
    dVydtauVy  ::  Array{Float64,2}
    dVxdtauVx0 ::  Array{Float64,2}
    dVydtauVy0 ::  Array{Float64,2}

    #[xc2,  yc2] = ndgrid(xc,yc);
    #[xvx2,yvx2] = ndgrid(xn,yc);
    #[xvy2,yvy2] = ndgrid(xc,yn);

    function Fields( mesh, Vbc, r, Tamp  )

        nx, Lx, dx = mesh.nx, mesh.Lx, mesh.dx
        ny, Ly, dy = mesh.ny, mesh.Ly, mesh.dy

        Vx         =  zeros(Float64, (nx+1,ny+2))
        Vy         =  zeros(Float64, (nx+2,ny+1))
        Vx        .=  Vbc * mesh.xn .* ones(ny+2)' ./Lx
        Vy        .= -Vbc * ones(nx+2).* transpose(mesh.yn) ./Ly
        T          =  zeros(Float64,(nx  ,ny  ))
        P          =  zeros(Float64,(nx  ,ny  ))
        etac       =   ones(Float64,(nx  ,ny  ))
        qx         =  zeros(Float64,(nx+1,ny  ))
        qy         =  zeros(Float64,(nx  ,ny+1))
        dVxdtauVx  =  zeros(Float64,(nx-1,ny  ))
        dVydtauVy  =  zeros(Float64,(nx  ,ny-1))
        dVxdtauVx0 =  zeros(Float64,(nx-1,ny  ))
        dVydtauVy0 =  zeros(Float64,(nx  ,ny-1))

        mask = ( mesh.xc.^2 .+ transpose(mesh.yc.^2) ) .< r^2

        T[mask] .= Tamp        # initial temperature pertubation

        new( Vx, Vy, T, P, etac, qx, qy, dVxdtauVx, dVydtauVy,
             dVxdtauVx0, dVydtauVy0 )

    end

end
