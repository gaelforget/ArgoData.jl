# -*- coding: utf-8 -*-
# ---
# jupyter:
#   jupytext:
#     cell_metadata_json: true
#     formats: ipynb,jl:light
#     text_representation:
#       extension: .jl
#       format_name: light
#       format_version: '1.5'
#       jupytext_version: 1.11.3
#   kernelspec:
#     display_name: Julia 1.7.2
#     language: julia
#     name: julia-1.7
# ---

# +
using ArgoData, DataFrames, CSV, NCDatasets, Plots

fil="ArgoToMITprof.yml"
meta=ArgoTools.mitprof_interp_setup(fil)
greylist=DataFrame(CSV.File(meta["dirIn"]*"../ar_greylist.txt"));
# -

meta

f=1
println(meta["dirIn"]*meta["fileInList"][f])
argo_data=Dataset(meta["dirIn"]*meta["fileInList"][f])
haskey(argo_data.dim,"N_PROF") ? np=argo_data.dim["N_PROF"] : np=NaN

m=1
prof=ArgoTools.GetOneProfile(argo_data,m)

argo_data["JULD"][1]

k=findall((!ismissing).(prof["T"]))[200]
prof["p"][k]-401.799987792968724

scatter(prof["S"],prof["T"])

# + {"cell_style": "split"}
#scatter(prof["T"],-prof["p"])

# + {"cell_style": "split"}
#scatter(prof["S"],-prof["p"])
# +
lonlatISbad=false
(prof["lat"]<-90.0)|(prof["lat"]>90.0) ? lonlatISbad=true : nothing
(prof["lon"]<-180.0)|(prof["lon"]>360.0) ? lonlatISbad=true : nothing

#if needed then reset lon,lat after issuing a warning
lonlatISbad==true ? println("warning: out of range lon/lat was reset to 0.0,-89.99") : nothing 
lonlatISbad ? (prof["lon"],prof["lat"])=(0.0,-89.99) : nothing

#if needed then fix longitude range to 0-360
(~lonlatISbad)&(prof["lon"]>180.0) ? prof["lon"]-=360.0 : nothing


# +
#if needed then convert pressure to depth
(~meta["inclZ"])&(~lonlatISbad) ? ArgoTools.prof_PtoZ!(prof,meta) : nothing
println(prof[meta["var_out"][1]][200]-398.625084513574966)

#if needed then convert T to potential temperature θ
meta["TPOTfromTINSITU"] ? ArgoTools.prof_TtoΘ!(prof,meta) : nothing
println(prof["T"][200]-13.80094224720384374)

T_step1=prof["T"]; S_step1=prof["S"]; D_step1=prof["depth"];

#interpolate to standard depth levels
ArgoTools.prof_interp!(prof,meta)

# + {"cell_style": "center"}
scatter(T_step1,-D_step1,title="temperature")
scatter!(prof["T"],-meta["z_std"])

# + {"cell_style": "center"}
scatter(S_step1,-D_step1,title="salinity")
scatter!(prof["S"],-meta["z_std"])
# -
# ## Interpolation coefficients for monthly climatology

# +
ff(x)=sin((x-0.5)/12*2pi)
fac,rec=ArgoTools.monthly_climatology_factors(prof["date"])

gg=fac[1]*ff(rec[1])+fac[2]*ff(rec[2])
(ff(rec[1]),gg,ff(rec[2]))
# -


