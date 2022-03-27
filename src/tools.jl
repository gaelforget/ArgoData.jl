module ArgoTools

using Dates, YAML, NCDatasets, CSV, DataFrames, Dierckx, Printf
import ArgoData.ProfileNative

"""
    mitprof_interp_setup(fil::String)

Get parameters etc from yaml file (`fil`).
"""
function mitprof_interp_setup(fil::String)

    meta=YAML.load(open(fil))

    #1. file list

    d=meta["dirIn"]
    b=meta["subset"]["basin"]
    y=meta["subset"]["year"]

    list0=Array{Array,1}(undef,12)
    for m=1:12
        sd="$b"*"_ocean/$y/"*Printf.@sprintf("%02d/",m)
        if isdir(d*sd)
            tmp=readdir(d*sd)
            list0[m]=[sd*tmp[i] for i=1:length(tmp)]
        else
            list0[m]=[]
        end
    end

    nf=sum(length.(list0))
    list1=Array{String,1}(undef,nf)
    f=0
    for m=1:12
        for ff=1:length(list0[m])
            f+=1
            list1[f]=list0[m][ff]
        end
    end

    meta["fileInList"]=list1;

    #2. coordinate

    z_std=meta["depthLevels"]
    if length(z_std)>1
        tmp1=(z_std[2:end]+z_std[1:end-1])/2
        z_top=[z_std[1]-(z_std[2]-z_std[1])/2;tmp1]
        z_bot=[tmp1;z_std[end]+(z_std[end]-z_std[end-1])/2]
    else
        z_top=0.9*z_std
        z_bot=1.1*z_std
    end

    meta["z_std"]=z_std
    meta["z_top"]=z_top
    meta["z_bot"]=z_bot

    #3. various other specs

    meta["inclZ"] = false
    meta["inclT"] = true
    meta["inclS"] = true
    meta["inclU"] = false
    meta["inclV"] = false
    meta["inclPTR"] = false
    meta["inclSSH"] = false
    meta["TPOTfromTINSITU"] = true

    meta["doInterp"] = true
    meta["addGrid"] = true
    meta["outputMore"] = false
    meta["method"] = "interp"
    meta["fillval"] = -9999.0
    meta["buffer_size"] = 10000

    meta["fileOut"]=meta["name"]*"_"*meta["subset"]["basin"]*"_"*string(meta["subset"]["year"])*".nc"
    meta["var_out"]=meta["variables"]
    
    return meta
end

"""
    GetOneProfile(m)

Get one profile from netcdf file.
"""
function GetOneProfile(ds,m)

    #
    t=ds["JULD"][m]
    ymd=Dates.year(t)*1e4+Dates.month(t)*1e2+Dates.day(t)
    hms=Dates.hour(t)*1e4+Dates.minute(t)*1e2+Dates.second(t)

    prof_date=t-DateTime(0)
    prof_date=prof_date.value/86400/1000 #days since DateTime(0)

    lat=ds["LATITUDE"][m]
    lon=ds["LONGITUDE"][m]
    lon < 0.0 ? lon=lon+360.0 : nothing

    direction=ds["DIRECTION"][m]
    direc=0
    direction=='A' ? direc=1 : nothing
    direction=='D' ? direc=2 : nothing

    #
    pnum_txt=ds["PLATFORM_NUMBER"][:,m]
    #pnum_txt=pnum_txt[findall((!ismissing).(pnum_txt))]
    ii=findall(skipmissing(in.(pnum_txt,"0123456789")))
    ~isempty(ii) ? pnum_txt=String(vec(Char.(pnum_txt[ii]))) : pnum_txt="9999"
    pnum=parse(Int,pnum_txt)

    #
    p=ds["PRES_ADJUSTED"][:,m]
    p_QC=ds["PRES_ADJUSTED_QC"][:,m]
    if sum((!ismissing).(p))==0
        p=ds["PRES"][:,m]
        p_QC=ds["PRES_QC"][:,m]
    end

    #set qc to 5 if missing
    p_QC[findall(ismissing.(p))].='5'
    #avoid potential duplicates
    for n=1:length(p)-1
        if ~ismissing(p[n])
            tmp1=( (!ismissing).(p[n+1:end]) ).&( p[n+1:end].==p[n] )
            tmp1=findall(tmp1)
            p[n.+tmp1].=missing
            p_QC[n.+tmp1].='5'
        end
    end

    #position and date
    isBAD=0
    ~in(ds["POSITION_QC"][m],"1258") ? isBAD=1 : nothing
    ~in(ds["JULD_QC"][m],"1258") ? isBAD=1 : nothing

    #pressure
    tmp1=findall( (!in).(p_QC,"1258") )
    if (length(tmp1)<=5)&&(length(tmp1)>0)
        #omit these few bad points but keep the profile
        p[tmp1].=missing
    elseif length(tmp1)>5
        #flag the profile (will be omitted later)
        #but keep the bad points (for potential inspection)
        isBAD=1
    end

    #temperature
    t=ds["TEMP_ADJUSTED"][:,m]
    t_QC=ds["TEMP_ADJUSTED_QC"][:,m]
    t_ERR=ds["TEMP_ADJUSTED_ERROR"][:,m]
    t_ERR[findall( (ismissing).(t_ERR) )].=0.0

    if sum((!ismissing).(t))==0
        t=ds["TEMP"][:,m]
        t_QC=ds["TEMP_QC"][:,m]
    end

    #salinity
    if haskey(ds,"PSAL")
        s=ds["PSAL_ADJUSTED"][:,m]
        s_QC=ds["PSAL_ADJUSTED_QC"][:,m]
        s_ERR=ds["PSAL_ADJUSTED_ERROR"][:,m]
        s_ERR[findall( (ismissing).(t_ERR) )].=0.0
        if sum((!ismissing).(t))==0
            s=ds["PSAL"][:,m]
            s_QC=ds["PSAL_QC"][:,m]
        end
    else
        s=fill(missing,size(t))
        s_QC=Char.(32*ones(size(t_QC)))
    end

    if ismissing(t[1]) #this file does not contain temperature data...
        t=fill(missing,size(t))
        t_ERR=fill(0.0,size(t))
    else #apply QC
        tmp1=findall(skipmissing((!in).(t_QC,"1258")))
        t[tmp1].=missing
    end

    if ismissing(s[1]) #this file does not contain salinity data...
        s=fill(missing,size(s))
        s_ERR=fill(0.0,size(s))
    else #apply QC
        tmp1=findall(skipmissing((!in).(s_QC,"1258")))
        s[tmp1].=missing
    end

    prof=ProfileNative(
        convert(Union{Float64,Missing},lon),
        convert(Union{Float64,Missing},lat),
        convert(Union{Float64,Missing},prof_date),
        convert(Union{Int,Missing},ymd),
        convert(Union{Int,Missing},hms),
        convert(Array{Union{Float64,Missing}},t),
        convert(Array{Union{Float64,Missing}},s),
        convert(Array{Union{Float64,Missing}},p),
        convert(Array{Union{Float64,Missing}},p), #place holder for depth
        convert(Array{Union{Float64,Missing}},t_ERR),
        convert(Array{Union{Float64,Missing}},s_ERR),
        pnum_txt,
        convert(Union{Int,Missing},direc),
        isBAD,
        ds["DATA_MODE"][m]
        )
    
    return prof
end

## ArgoProfile data structure

"""
    prof_PtoZ!(prof)

Convert prof["p"] to prof["depth"]
"""
function prof_PtoZ!(prof)
    l=prof.lat
    k=findall((!ismissing).(prof.pressure))
    prof.depth[k].=[sw_dpth(Float64(prof.pressure[kk]),Float64(l)) for kk in k]
end

"""
    prof_TtoΘ!(prof)

Convert prof["T"] to potential temperature
"""
function prof_TtoΘ!(prof)
    T=prof.T
    P=0.981*1.027*prof.depth
    S=35.0*ones(size(T))
    k=findall( (!ismissing).(T) )
    T[k]=[sw_ptmp(Float64(S[kk]),Float64(T[kk]),Float64(P[kk])) for kk in k]
end


"""
    prof_interp!(prof,meta)

Interpolate from prof["depth"] to meta["z_std"]
"""
function prof_interp!(prof,prof_std,meta)
    z_std=meta["z_std"]
    for ii=2:length(meta["var_out"])
        v=meta["var_out"][ii]
        v_e=v*"_ERR"

        t_std=similar(z_std,Union{Missing,Float64})
        e_std=similar(z_std,Union{Missing,Float64})

        z=prof.depth
        v=="T" ? t=prof.T : t=prof.S
        do_e=true #haskey(prof,v_e)
        v=="T" ? e=prof.T_ERR : e=prof.S_ERR

        kk=findall((!ismissing).(z.*t))
        if (meta["doInterp"])&&(length(kk)>1)
            z_in=z[kk]; t_in=t[kk]
            do_e ? e_in=e[kk] : nothing
            k=sort(1:length(kk),by= i -> z_in[i])
            z_in=z_in[k]; t_in=t_in[k]
            do_e ? e_in=e_in[k] : nothing
            #omit values outside observed range:
            D0=minimum(skipmissing(z_in))
            D1=maximum(skipmissing(z_in))
            msk1=findall( (z_std.<D0).|(z_std.>D1) )
            #avoid duplicates:
            msk2=findall( ([false;(z_in[1:end-1]-z_in[2:end]).==0.0]).==true )
            if length(kk)>5
                spl = Spline1D(z_in, t_in)
                t_std[:] = spl(z_std)
                t_std[msk1].=missing
                t_std[msk2].=missing
                if do_e
                    e_in[findall(ismissing.(e_in))].=0.0
                    spl = Spline1D(z_in, e_in)
                    e_std[:] = spl(z_std)
                    e_std[msk1].=missing
                    e_std[msk2].=missing
                end
            else
                t_std = []
                e_std = []
            end
        end
        if v=="T"
            prof_std.T .=t_std
            prof_std.T_ERR .=e_std
        else
            prof_std.S .=t_std
            prof_std.S_ERR .=e_std
        end
    end
end


"""
    prof_convert!(prof,meta)

Appply conversions to variables (lon,lat,depth,temperature) in `prof` if specified in `meta`.
"""
function prof_convert!(prof,meta)
    lonlatISbad=false
    (prof.lat<-90.0)|(prof.lat>90.0) ? lonlatISbad=true : nothing
    (prof.lon<-180.0)|(prof.lon>360.0) ? lonlatISbad=true : nothing

    #if needed then reset lon,lat after issuing a warning
    lonlatISbad==true ? println("warning: out of range lon/lat was reset to 0.0,-89.99") : nothing 
    lonlatISbad ? (prof.lon,prof.lat)=(0.0,-89.99) : nothing

    #if needed then fix longitude range to 0-360
    (~lonlatISbad)&(prof.lon>180.0) ? prof.lon-=360.0 : nothing
    
    #if needed then convert pressure to depth
    (~meta["inclZ"])&(~lonlatISbad) ? ArgoTools.prof_PtoZ!(prof) : nothing

    #if needed then convert T to potential temperature θ
    meta["TPOTfromTINSITU"] ? ArgoTools.prof_TtoΘ!(prof) : nothing
end

function interp1(x,y,xi)
    jj=findall(isfinite.(y))
    spl = Spline1D(x[jj], y[jj], k=1, bc="nearest")
    return spl(xi)
end

"""
    sw_dpth(P,LAT)

Calculate depth in meters from pressure (P; in decibars) and
latitude (LAT; in °N)

```
d = sw_dpth(100.0,20.0)
```
"""
function sw_dpth(P,LAT)
    # Original author:  Phil Morgan 92-04-06  (morgan@ml.csiro.au)
    # Reference: Unesco 1983. Algorithms for computation of fundamental properties of
    # seawater, 1983. _Unesco Tech. Pap. in Mar. Sci._, No. 44, 53 pp. Eqn 25, p26

    c1 = 9.72659
    c2 = -2.2512E-5
    c3 = 2.279E-10
    c4 = -1.82E-15
    gam_dash = 2.184e-6

    LAT = abs.(LAT)
    X   = sin.(deg2rad.(LAT))
    X   = X.*X
    bot_line = 9.780318*(1.0+(5.2788E-3+2.36E-5*X).*X) + gam_dash*0.5*P
    top_line = (((c4*P+c3).*P+c2).*P+c1).*P
    DEPTHM   = top_line./bot_line

    return DEPTHM
end

"""
    sw_ptmp(S,T,P,PR)

Calculate potential temperature as per UNESCO 1983 report from salinity (S;
in psu), in situ temperature (T; in °C), and pressure (P; in decibar)
relative to PR (in decibar; 0 by default).

```
ptmp = sw_ptmp(S,T,P,PR=missing)
```
"""
function sw_ptmp(S,T,P,PR=0.0)
# Original author:  Phil Morgan
# Reference: Fofonoff, P. and Millard, R.C. Jr
#    Unesco 1983. Algorithms for computation of fundamental properties of
#    seawater. _Unesco Tech. Pap. in Mar. Sci._, No. 44. Eqn.(31) p.39
#    Bryden, H. 1973.
#    "New Polynomials for thermal expansion, adiabatic temperature gradient
#    and potential temperature of sea water." DEEP-SEA RES., 1973, Vol 20

# theta1
del_P  = PR - P
del_th = del_P.*sw_adtg(S,T,P);
th     = T + 0.5*del_th;
q      = del_th;

# theta2
del_th = del_P.*sw_adtg(S,th,P+0.5*del_P);
th     = th + (1 - 1/sqrt(2))*(del_th - q);
q      = (2-sqrt(2))*del_th + (-2+3/sqrt(2))*q;

# theta3
del_th = del_P.*sw_adtg(S,th,P+0.5*del_P);
th     = th + (1 + 1/sqrt(2))*(del_th - q);
q      = (2 + sqrt(2))*del_th + (-2-3/sqrt(2))*q;

# theta4
del_th = del_P.*sw_adtg(S,th,P+del_P);
PT     = th + (del_th - 2*q)/6;

return PT
end


"""
    sw_adtg(S,T,P)

Calculate adiabatic temperature gradient as per UNESCO 1983 routines from salinity
(S; in psu), in situ temperature (T; in °C), and pressure (P; in decibar)
```
adtg = sw_adtg(S,T,P)
```
"""
function sw_adtg(S,T,P)
    # Original author:  Phil Morgan
    # Reference: Fofonoff, P. and Millard, R.C. Jr
    #    Unesco 1983. Algorithms for computation of fundamental properties of
    #    seawater. _Unesco Tech. Pap. in Mar. Sci._, No. 44. Eqn.(31) p.39
    #    Bryden, H. 1973.
    #    "New Polynomials for thermal expansion, adiabatic temperature gradient
    #    and potential temperature of sea water." DEEP-SEA RES., 1973, Vol 20

    a0 =  3.5803E-5;
    a1 =  8.5258E-6;
    a2 = -6.836E-8;
    a3 =  6.6228E-10;

    b0 =  1.8932E-6;
    b1 = -4.2393E-8;

    c0 =  1.8741E-8;
    c1 = -6.7795E-10;
    c2 =  8.733E-12;
    c3 = -5.4481E-14;

    d0 = -1.1351E-10;
    d1 =  2.7759E-12;

    e0 = -4.6206E-13;
    e1 =  1.8676E-14;
    e2 = -2.1687E-16;

    ADTG =      a0 + (a1 + (a2 + a3.*T).*T).*T + (b0 + b1.*T).*(S-35.0) +
    ( (c0 + (c1 + (c2 + c3.*T).*T).*T) + (d0 + d1.*T).*(S-35.0) ).*P +
    (  e0 + (e1 + e2.*T).*T ).*P.*P

    return ADTG
end

"""
    monthly_climatology_factors(date)

if `date` is a date in `days since DateTime(0)`

and `ff(rec)` returns a value for month `rec` in `1:12`

then compute the factors to interpolate from `rec[1],rec[2]` to `date`.

For example :

```
ff(x)=sin((x-0.5)/12*2pi)
fac,rec=monthly_climatology_factors(prof["date"])

gg=fac[1]*ff(rec[1])+fac[2]*ff(rec[2])
(ff(rec[1]),gg,ff(rec[2]))
```
"""
function monthly_climatology_factors(date)
    
    tmp2=ones(13,1)*[1991 1 1 0 0 0]; tmp2[1:12,2].=(1:12); tmp2[13,1]=1992.0;
    tmp2=[DateTime(tmp2[i,:]...) for i in 1:13]
    
    tim_fld=tmp2 .-DateTime(1991,1,1); 
    tim_fld=1/2*(tim_fld[1:12]+tim_fld[2:13])    
    tim_fld=[tim_fld[i].value for i in 1:12]/86400/1000
    
    tim_fld=[tim_fld[12]-365.0;tim_fld...;tim_fld[1]+365.0]
    rec_fld=[12;1:12;1]
    
#    year0=floor(profIn["ymd"]/1e4)    
    year0=year(DateTime(0,1,1)+Day(Int(floor(date))))
    date0=DateTime(year0,1,1)-DateTime(0)

    date0=date0.value/86400/1000    
    tim_prof=date-date0
    tim_prof>365.0 ? tim_prof=365.0 : nothing

    #tim_fld,rec_fld,tim_prof

    tt=maximum(findall(tim_fld.<=tim_prof))
    a0=(tim_prof-tim_fld[tt])/(tim_fld[tt+1]-tim_fld[tt])
    
    return (1-a0,a0),(rec_fld[tt],rec_fld[tt+1])
end

end