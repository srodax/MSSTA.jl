using Test
using ITensors
ITensors.disable_warn_order()
using MSSTA
import Random

@testset "binaryop.jl" begin
    @testset "_binaryop" for rev_carrydirec in [true], nbit in 2:3
        Random.seed!(1)
        # For a = +/- 1, b = +/- 1, c = +/- 1, d = +/- 1,
        # x' = a * x + b * y
        # y' = c * x + d * y
        # f(x, y) = g(x', y')
        # excluding a + b == -2 || c + d == -2
        if rev_carrydirec
            # x1, y1, x2, y2, ...
            sites = [Index(2, "Qubit, $name=$n") for n in 1:nbit for name in ["x", "y"]]
        else
            # xR, yR, xR-1, yR-1, ...
            sites = [Index(2, "Qubit, $name=$n") for n in reverse(1:nbit)
                     for name in ["x", "y"]]
        end
        # x1, x2, ...
        sitesx = [sites[findfirst(x -> hastags(x, "x=$n"), sites)] for n in 1:nbit]
        # y1, y2, ...
        sitesy = [sites[findfirst(x -> hastags(x, "y=$n"), sites)] for n in 1:nbit]
        rsites = reverse(sites)

        for a in -1:1, b in -1:1, c in -1:1, d in -1:1, bc_x in [1, -1], bc_y in [1, -1]
            g = randomMPS(sites)
            M = MSSTA._binaryop_mpo(sites, [(a, b), (c, d)], [(1, 2), (1, 2)];
                               rev_carrydirec=rev_carrydirec, bc=[bc_x, bc_y])
            f = apply(M, g)

            # f[x_R, ..., x_1, y_R, ..., y_1] and f[x, y]
            f_arr = Array(reduce(*, f), vcat(reverse(sitesx), reverse(sitesy)))
            f_vec = reshape(f_arr, 2^nbit, 2^nbit)

            # g[x_R, ..., x_1, y_R, ..., y_1] and g[x, y]
            g_arr = Array(reduce(*, g), vcat(reverse(sitesx), reverse(sitesy)))
            g_vec = reshape(g_arr, 2^nbit, 2^nbit)

            function prime_xy(x, y)
                0 <= x < 2^nbit || error("something went wrong")
                0 <= y < 2^nbit || error("something went wrong")
                xp_ = a * x + b * y
                yp_ = c * x + d * y
                nmodx, xp = divrem(xp_, 2^nbit, RoundDown)
                nmody, yp = divrem(yp_, 2^nbit, RoundDown)
                return xp, yp, bc_x^nmodx, bc_y^nmody
            end

            f_vec_ref = similar(f_vec)
            for x in 0:(2^nbit - 1), y in 0:(2^nbit - 1)
                xp, yp, sign_x, sign_y = prime_xy(x, y)
                f_vec_ref[x + 1, y + 1] = g_vec[xp + 1, yp + 1] * sign_x * sign_y
            end

            @test f_vec_ref ≈ f_vec
        end
    end

    @testset "affinetransform" for rev_carrydirec in [true, false], nbit in 2:3
        Random.seed!(1)
        # For a, b, c, d = +1, -1, 0,
        #   x' = a * x + b * y + s1
        #   y' = c * x + d * y + s2
        # f(x, y) = g(x', y')
        if rev_carrydirec
            # x1, y1, x2, y2, ...
            sites = [Index(2, "Qubit, $name=$n") for n in 1:nbit for name in ["x", "y"]]
        else
            # xR, yR, xR-1, yR-1, ...
            sites = [Index(2, "Qubit, $name=$n") for n in reverse(1:nbit)
                     for name in ["x", "y"]]
        end
        # x1, x2, ...
        sitesx = [sites[findfirst(x -> hastags(x, "x=$n"), sites)] for n in 1:nbit]
        # y1, y2, ...
        sitesy = [sites[findfirst(x -> hastags(x, "y=$n"), sites)] for n in 1:nbit]
        shift = rand(-2*2^nbit:2*2^nbit, 2)

        for a in -1:1, b in -1:1, c in -1:1, d in -1:1, bc_x in [1, -1], bc_y in [1, -1]
            g = randomMPS(sites)
            f = MSSTA.affinetransform(
                g, ["x", "y"], [Dict("x"=>a, "y"=>b), Dict("x"=>c, "y"=>d)],
                shift, [bc_x, bc_y], cutoff=1e-25)

            # f[x_R, ..., x_1, y_R, ..., y_1] and f[x, y]
            f_arr = Array(reduce(*, f), vcat(reverse(sitesx), reverse(sitesy)))
            f_vec = reshape(f_arr, 2^nbit, 2^nbit)

            # g[x_R, ..., x_1, y_R, ..., y_1] and g[x, y]
            g_arr = Array(reduce(*, g), vcat(reverse(sitesx), reverse(sitesy)))
            g_vec = reshape(g_arr, 2^nbit, 2^nbit)

            function prime_xy(x, y)
                0 <= x < 2^nbit || error("something went wrong")
                0 <= y < 2^nbit || error("something went wrong")
                xp_ = a * x + b * y + shift[1]
                yp_ = c * x + d * y + shift[2]
                nmodx, xp = divrem(xp_, 2^nbit, RoundDown)
                nmody, yp = divrem(yp_, 2^nbit, RoundDown)
                return xp, yp, bc_x^nmodx, bc_y^nmody
            end

            f_vec_ref = similar(f_vec)
            for x in 0:(2^nbit - 1), y in 0:(2^nbit - 1)
                xp, yp, sign_x, sign_y = prime_xy(x, y)
                f_vec_ref[x + 1, y + 1] = g_vec[xp + 1, yp + 1] * sign_x * sign_y
            end

            @test f_vec_ref ≈ f_vec
        end
    end

    #===
    pos_sites_in: [(1, 2), (2, 3), (3, 1)]
      x' = c1 * x + c2 * y
      y' =          c3 * y + c4 * z
      z' = c6 * x          + c5 * z
    ===#

    #==
    #@testset "binaryop_three_sites" for rev_carrydirec in [true, false], bc_x in [1, -1], bc_y in [1, -1], bc_z in [1, -1], nbit in 2:3
    @testset "binaryop_three_sites" for rev_carrydirec in [true], bc_x in [1], bc_y in [1], bc_z in [1], nbit in [2]
        # x' = c1 * x + c2 * y
        # y' =          c3 * y + c4 * z
        # z' = c6 * x          + c5 * z
        # f(x, y, z) = g(x', y', z')
        if rev_carrydirec
            # x1, y1, z1, x2, y2, z2, ...
            sites = [Index(2, "Qubit, $name=$n") for n in 1:nbit for name in ["x", "y", "z"]]
        else
            # xR, yR, zR, xR-1, yR-1, zR-1...
            sites = [Index(2, "Qubit, $name=$n") for n in reverse(1:nbit)
                     for name in ["x", "y", "z"]]
        end
        # x1, x2, ...
        sitesx = [sites[findfirst(x -> hastags(x, "x=$n"), sites)] for n in 1:nbit]
        # y1, y2, ...
        sitesy = [sites[findfirst(x -> hastags(x, "y=$n"), sites)] for n in 1:nbit]
        # z1, z2, ...
        sitesz = [sites[findfirst(x -> hastags(x, "z=$n"), sites)] for n in 1:nbit]

        rsites = reverse(sites)

        #for coeffs in Iterators.product(fill(collect(-1:1), 6)...)
        for coeffs in [(-1, -1, 1, 1, 1, 1)]
            M = MSSTA.binaryop_mpo(
                sites,
                [Tuple(coeffs[1:2]), Tuple(coeffs[3:4]), Tuple(coeffs[5:6])],
                [(1, 2), (2, 3), (3, 1)];
                rev_carrydirec=rev_carrydirec, bc=[bc_x, bc_y, bc_z])

            f = randomMPS(sites)
            g = apply(M, f)

            # f[x_R, ..., x_1, y_R, ..., y_1, z_R, ..., z_1]
            f_arr = Array(reduce(*, f), vcat(reverse(sitesx), reverse(sitesy), reverse(sitesz)))

            # g[x'_R, ..., x'_1, y'_R, ..., y'_1, z'_R, ..., z'_1]
            g_arr = Array(reduce(*, g), vcat(reverse(sitesx), reverse(sitesy), reverse(sitesz)))

            # f[x, y, z]
            f_vec = reshape(f_arr, 2^nbit, 2^nbit, 2^nbit)

            # g[x', y', z']
            g_vec = reshape(g_arr, 2^nbit, 2^nbit, 2^nbit)

            function prime_xy(x, y, z)
                xp_ = coeffs[1] * x + coeffs[2] * y
                yp_ =                 coeffs[3] * y + coeffs[4] * z
                zp_ = coeffs[6] * x                 + coeffs[5] * z
                nmodx, xp = divrem(xp_, 2^nbit, RoundDown)
                nmody, yp = divrem(yp_, 2^nbit, RoundDown)
                nmodz, zp = divrem(zp_, 2^nbit, RoundDown)
                return xp, yp, zp, bc_x^nmodx, bc_y^nmody, bc_z^nmodz
            end

            g_vec_ref = similar(g_vec)
            for x in 0:(2^nbit - 1), y in 0:(2^nbit - 1), z in 0:(2^nbit - 1)
                xp, yp, zp, sign_x, sign_y, sign_z = prime_xy(x, y, z)
                g_vec_ref[x + 1, y + 1, z + 1] = f_vec[xp + 1, yp + 1, zp+1] * sign_x * sign_y * sign_z
            end

            @test g_vec_ref ≈ g_vec
        end
    end
    ==#

    @testset "shiftop" for R in [3], bc in [1, -1]
        sites = [Index(2, "Qubit, x=$n") for n in 1:R]
        g = randomMPS(sites)

        for shift in [0, 1, 2, 2^R-1]
            M = MSSTA._shift_mpo(sites, shift; bc=bc)
            f = apply(M, g)

            f_vec = vec(Array(reduce(*, f), reverse(sites)))
            g_vec = vec(Array(reduce(*, g), reverse(sites)))

            f_vec_ref = similar(f_vec)
            for i in 1:2^R
                ishifted = mod1(i + shift, 2^R)
                sign = ishifted == i + shift ? 1 : bc
                f_vec_ref[i] = g_vec[ishifted] * sign
            end

            @test f_vec_ref ≈ f_vec
        end
    end
end

