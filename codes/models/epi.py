"""
Functions to help in infectious disease simulation.
"""

import warnings
from collections import OrderedDict

import numpy as np

import pandas as pd
import xarray as xr
from statsmodels.api import OLS, add_constant


def init_reg_ds(n_samples, LHS_vars, policies, **dim_kwargs):
    """
    Initialize a Dataset to place regression estimates
    """

    coords = {
        "sample": range(n_samples),
    }
    coords = {**coords, **dim_kwargs}

    estimate_coords = {**coords, **{"LHS": LHS_vars, "policy": list(policies)}}

    estimates = xr.DataArray(
        coords=estimate_coords, dims=estimate_coords.keys(), name="coefficient"
    )
    s_mins = xr.DataArray(coords=coords, dims=coords.keys(), name="S_min")
    s_mins_p3 = s_mins.copy()
    s_mins_p3.name = "S_min_p3"

    return xr.merge([estimates, s_mins, s_mins_p3])


def init_state_arrays(shp, n_arrays):
    return [np.ones(shp) * np.nan for a in range(n_arrays)]


def adjust_timescales_from_daily(ds, tstep, to=False):
    out = ds.copy()
    for k, v in ds.variables.items():
        if k.split("_")[0] in [
            "lambda",
            "beta",
            "gamma",
            "sigma",
        ]:
            # staying in continuous rate
            out[k] = out[k] * tstep
    return out


def adjust_timescales_to_daily(ds, tsteps_per_day):
    """
    Adjusts from discrete rates used for SIR model to daily continuous rates
    """
    out = ds.copy()
    tstep = ds.t[1] - ds.t[0]
    coord_cols = [k for k in ds.coords if k in ["lambda", "beta", "gamma", "sigma"]]
    cols = [
        k
        for k, v in ds.variables.items()
        if k.split("_")[0] in ["lambda", "beta", "gamma", "sigma"]
        and k not in coord_cols
    ]

    out = ds.isel(t=slice(0, -1, tsteps_per_day))

    def scale_up_disc_to_cont(x):
        return np.log((x + 1).prod(dim="t"))

    for c in cols + coord_cols:
        if "t" in ds[c].dims:
            out[c].values = (
                ds[c]
                .isel(t=slice(None, -1))
                .groupby(ds.t.astype(int)[:-1])
                .map(scale_up_disc_to_cont)
                .values
            )
        else:
            out[c] = np.log((1 + ds.isel(t=slice(None, -1))[c]) ** (1 / tstep))
            if c in coord_cols:
                out[c] = out[c].round(5)
    return out


def init_policy_dummies(policy_ds, n_samples, t, seed=0, random_end=False):
    """
    Initialize dummy variables to define policy effects
    """

    np.random.seed(seed)
    n_effects = policy_ds.policy.shape[0]
    n_steps = len(t)
    steps_per_day = int(np.round(1 / ((t.max() - t.min()) / (t.shape[0] - 1))))

    # initialized double as many b/c we will drop collinear ones
    dates = np.random.randint(
        policy_ds.interval.sel(time="start"),
        policy_ds.interval.sel(time="end"),
        (n_samples * 2, n_effects),
    )
    dates.sort(axis=1)

    # drop any with complete collinearity of policies
    valid = np.apply_along_axis(lambda x: len(np.unique(x)) == dates.shape[1], 1, dates)

    # confirm we still have n_samples left after dropping
    assert valid.sum() > n_samples
    dates = dates[valid]
    dates = dates[:n_samples]

    # determine random end point of regression, if desired
    if random_end:
        random_end_arr = np.random.uniform(size=(n_samples,))
    else:
        random_end_arr = np.ones(n_samples)

    # create policy dummy array
    comp = np.repeat(np.arange(n_steps)[:, np.newaxis], dates.shape[1], axis=1)
    out = (comp.T[np.newaxis, ...] >= dates[..., np.newaxis] * steps_per_day).astype(
        float
    )

    # get lags in appropriate timesteps
    lags = []
    for l in policy_ds.policy:
        this_lag = policy_ds.lag.sel(policy=l.item())
        this_new_lag = []
        for i in this_lag:
            this_new_lag += [i] * steps_per_day
        lags.append(this_new_lag)

    # adjust for lags
    p_on = out.argmax(axis=-1)
    for lx, l in enumerate(lags):
        for sx in range(out.shape[0]):
            this_p_on = p_on[sx, lx]
            out[sx, lx, this_p_on : this_p_on + len(l)] = l

    out = out.swapaxes(1, 2)
    coords = OrderedDict(sample=range(n_samples), t=t, policy=policy_ds.policy,)
    out = xr.DataArray(out, coords=coords, dims=coords.keys(), name="policy_timeseries")
    return (
        out,
        xr.DataArray(
            random_end_arr,
            coords={"sample": range(n_samples)},
            dims=["sample"],
            name="random_end",
        ),
    )


def get_beta_SEIR(lambdas, gammas, sigmas):
    """
    In a SEIR model, $\beta$ in a S~=1 setting is a function of the exponential growth 
    rate ($\lambda$), $\sigma$, and $\gamma$. This calculates that based on the deterministic gamma and 
    sigmas.
    """
    return (lambdas + gammas) * (lambdas + sigmas) / sigmas


def get_beta_SIR(lambdas, gammas, *args):
    return lambdas + gammas


def get_lambda_SEIR(betas, gammas, sigmas):
    return (
        -(sigmas + gammas) + np.sqrt((sigmas - gammas) ** 2 + 4 * sigmas * betas)
    ) / 2


def get_lambda_SIR(betas, gammas, *args):
    return betas - gammas


def apply_noise(out, params, noise_types, shape=(0,), noise_sds=[0], seed=0):
    np.random.seed(seed)
    for px, param in enumerate(params):
        noise_type = noise_types[px]
        noise_sd = noise_sds[px]
        param_stoch = param + "_stoch"
        param_det = param + "_deterministic"
        if noise_type is None:
            continue
        elif noise_type == "normal":
            out[param_stoch] = (
                ("sample", "t"),
                np.random.normal(0, noise_sd, shape),
            )
            out[param_stoch] = out[param_det] + out[param_stoch]
        elif noise_type == "exponential":
            (out[param_det], _, _) = xr.broadcast(out[param_det], out.sample, out.t)
            out[param_stoch] = (
                out[param_det].dims,
                np.random.exponential(out[param_det]),
            )
        # commented out b/c inverse-exponential has undefined expected value
        # and empirically changes the mean parameter by order(s) of magnitude
        #         elif noise_type == "inv_exponential":
        #             (out[param_det],_,_) = xr.broadcast(out[param_det], out.sample, out.t)
        #             out[param_stoch] = (
        #                 out[param_det].dims,
        #                 1/np.random.exponential(1/out[param_det])
        #             )
        elif not noise_type:
            out[param_stoch] = out[param_det].copy()
        else:
            raise ValueError(noise_type)
        neg = out[param_stoch] < 0
        n_bad = neg.sum().item()
        if n_bad > 0:
            n_tot = np.prod(out[param_stoch].shape)
            dims = ["gamma"]
            if "sigma" in out[param_stoch].dims:
                dims.append("sigma")
            to_sum = [d for d in out[param_stoch].dims if d not in dims]
            cross_tab = (neg.sum(to_sum) / neg.count(to_sum)).to_dataframe()
            warnings.warn(
                f"Parameter {param} has {n_bad}/{n_tot} values <0 ({n_bad/n_tot:.2%}). These are non-physical params. "
                f"If they are dropped in the simulation, this will change the mean. Fraction of negative values: {cross_tab}"
            )
    return out


def get_stochastic_discrete_params(
    estimates_ds,
    no_policy_growth_rate,
    policy_effect_timeseries,
    t,
    beta_noise_on,
    beta_noise_sd,
    kind="SIR",
    gamma_noise_on=None,
    gamma_noise_sd=None,
    sigma_noise_on=False,
    sigma_noise_sd=None,
    seed=0,
):

    if kind == "SIR":
        beta_func = get_beta_SIR
        lambda_func = get_lambda_SIR
    elif kind == "SEIR":
        beta_func = get_beta_SEIR
        lambda_func = get_lambda_SEIR
    else:
        raise ValueError(kind)
    out = estimates_ds.copy()

    # this is the discrete short-timestep eigenvalue for a zero-mean beta
    tstep = t[1] - t[0]
    out["lambda_disc_meanbeta"] = (
        np.exp((no_policy_growth_rate + policy_effect_timeseries) * tstep) - 1
    )

    if "sample" not in out.dims:
        out = out.expand_dims("sample")

    for param in ["gamma", "sigma"]:
        if f"{param}_deterministic" not in out:
            out[f"{param}_deterministic"] = out[param].copy()
        # discretize
        out[f"{param}_deterministic"] = np.exp(out[f"{param}_deterministic"]) - 1
        out[param] = np.exp(out[param]) - 1

    sampXtime = (len(out.sample), len(out.t))
    out_vars = ["beta_stoch", "gamma_stoch"]

    out["beta_deterministic"] = beta_func(
        out.lambda_disc_meanbeta, out.gamma, out.sigma
    )

    these_params = ["beta", "gamma"]
    these_noise = [beta_noise_on, gamma_noise_on]
    these_sd = [beta_noise_sd, gamma_noise_sd]
    if "sigma" in out.dims:
        these_params.append("sigma")
        these_noise.append(sigma_noise_on)
        these_sd.append(sigma_noise_sd)

    out = apply_noise(
        out, these_params, these_noise, shape=sampXtime, noise_sds=these_sd, seed=seed
    )
    out["lambda_stoch"] = lambda_func(out.beta_stoch, out.gamma_stoch, out.sigma_stoch)

    return out


def run_SIR(I0, R0, ds):
    """
    Simulate SIR model using forward euler integration. All states are defined as 
    fractions of a population.
    """
    n_steps = len(ds.t)

    new_dims = ["t"] + [i for i in ds.beta_stoch.dims if i != "t"]
    beta = ds.beta_stoch.transpose(*new_dims)
    gamma = ds.gamma_stoch.broadcast_like(beta)

    S, I, R = init_state_arrays(beta.shape, 3)

    # initial conditions
    R[0] = R0
    I[0] = I0
    S[0] = 1 - I[0] - R[0]

    for i in range(1, n_steps):
        new_infected_rate = beta[i - 1] * S[i - 1]
        new_removed_rate = gamma[i - 1]

        S[i] = S[i - 1] - new_infected_rate * I[i - 1]
        I[i] = I[i - 1] * np.exp(new_infected_rate - new_removed_rate)
        R[i] = 1 - S[i] - I[i]

    out = ds.copy()
    for ox, o in enumerate([S, I, R]):
        name = "SIR"[ox]
        out[name] = (new_dims, o)

    return out


def run_SEIR(E0, I0, R0, ds):
    """
    Simulate SEIR model using forward euler integration. All states are defined as 
    fractions of a population.
    """

    n_steps = len(ds.t)

    new_dims = ["t"] + [i for i in ds.beta_stoch.dims if i != "t"]

    beta = ds.beta_stoch.transpose(*new_dims)
    gamma = ds.gamma_stoch.broadcast_like(beta)
    sigma = ds.sigma_stoch.broadcast_like(beta)

    S, E, I, R = init_state_arrays(beta.shape, 4)

    # initial conditions
    R[0] = R0
    I[0] = I0
    E[0] = E0
    S[0] = 1 - I[0] - R[0] - E[0]

    for i in range(1, n_steps):
        new_exposed = beta[i - 1] * S[i - 1] * I[i - 1]
        new_infected = sigma[i - 1] * E[i - 1]
        new_removed = gamma[i - 1] * I[i - 1]

        S[i] = S[i - 1] - new_exposed
        E[i] = E[i - 1] + new_exposed - new_infected
        I[i] = I[i - 1] + new_infected - new_removed
        R[i] = 1 - S[i] - E[i] - I[i]

    out = ds.copy()
    for ox, o in enumerate([S, E, I, R]):
        name = "SEIR"[ox]
        out[name] = (new_dims, o)

    return out


def add_obs_noise(daily_ds, measurement_noise_on=False, measurement_noise_sd=0):
    if measurement_noise_on == "normal":
        daily_ds["meas_noise"] = (
            ("sample", "t"),
            np.random.normal(
                0, measurement_noise_sd, (daily_ds.dims["sample"], daily_ds.dims["t"])
            ),
        )
        daily_ds["logdiff_stoch"] = daily_ds.logdiff + daily_ds.meas_noise
    elif measurement_noise_on == "exponential":
        daily_ds["logdiff_stoch"] = np.random.exponential(daily_ds.logdiff)
    elif not measurement_noise_on:
        daily_ds["logdiff_stoch"] = daily_ds.logdiff
    else:
        raise ValueError(measurement_noise_on)
    return daily_ds


def simulate_and_regress(
    pop,
    no_policy_growth_rate,
    p_effects,
    p_lags,
    p_start_interval,
    n_days,
    tsteps_per_day,
    n_samples,
    LHS_vars,
    reg_lag_days,
    gamma_to_test,
    min_cases,
    sigma_to_test=[np.nan],
    measurement_noise_on=False,
    measurement_noise_sd=0,
    beta_noise_on=False,
    beta_noise_sd=0,
    sigma_noise_on=False,
    sigma_noise_sd=0,
    gamma_noise_on=False,
    gamma_noise_sd=0,
    kind="SEIR",
    E0=1,
    I0=0,
    R0=0,
    random_end=False,
    save_dir=None,
):

    attrs = dict(
        E0=E0,
        I0=I0,
        R0=R0,
        pop=pop,
        min_cases=min_cases,
        measurement_noise_on=str(measurement_noise_on),
        beta_noise_on=str(beta_noise_on),
        gamma_noise_on=str(gamma_noise_on),
        measurement_noise_sd=measurement_noise_sd,
        beta_noise_sd=beta_noise_sd,
        gamma_noise_sd=gamma_noise_sd,
        no_policy_growth_rate=no_policy_growth_rate,
        tsteps_per_day=tsteps_per_day,
        p_effects=p_effects,
    )

    E0 = E0 / pop
    I0 = I0 / pop
    R0 = R0 / pop

    ## setup
    if kind == "SEIR":
        attrs["sigma_noise_on"] = str(sigma_noise_on)
        attrs["sigma_noise_sd"] = sigma_noise_sd
        sim_engine = run_SEIR
        get_beta = get_beta_SEIR
        ics = [E0, I0, R0]
    elif kind == "SIR":
        sigma_to_test = [np.nan]
        sigma_noise_on = False
        sim_engine = run_SIR
        get_beta = get_beta_SIR
        ics = [I0, R0]
        LHS_vars = [l for l in LHS_vars if "E" not in l]

    # get time vector
    ttotal = n_days * tsteps_per_day + 1
    t = np.linspace(0, 1, ttotal) * n_days

    # store policy info
    policies = xr.Dataset(
        coords={
            "policy": [f"p{i+1}" for i in range(len(p_effects))],
            "time": ["start", "end"],
            "lag_num": range(len(p_lags[0])),
        },
        data_vars={
            "effect": (("policy",), p_effects),
            "lag": (("policy", "lag_num"), p_lags),
            "interval": (("time",), p_start_interval),
        },
    )

    # initialize results array
    estimates_ds = init_reg_ds(
        n_samples,
        LHS_vars,
        policies.policy.values,
        gamma=gamma_to_test,
        sigma=sigma_to_test,
    )

    # get policy effects
    policy_dummies, random_end_da = init_policy_dummies(
        policies, n_samples, t, seed=0, random_end=random_end
    )
    policies = xr.merge((policies, policy_dummies, random_end_da))
    policy_effect_timeseries = (policies.policy_timeseries * policies.effect).sum(
        "policy"
    )
    n_samp_valid = len(policies.sample)

    # adjust rate params to correct timestep
    estimates_ds = adjust_timescales_from_daily(estimates_ds, t[1] - t[0])
    beta_noise_sd = beta_noise_sd / np.sqrt(tsteps_per_day)
    gamma_noise_sd = gamma_noise_sd / np.sqrt(tsteps_per_day)
    sigma_noise_sd = sigma_noise_sd / np.sqrt(tsteps_per_day)

    # get stochastic params
    estimates_ds = get_stochastic_discrete_params(
        estimates_ds,
        no_policy_growth_rate,
        policy_effect_timeseries,
        t,
        beta_noise_on,
        beta_noise_sd,
        kind=kind,
        gamma_noise_on=gamma_noise_on,
        gamma_noise_sd=gamma_noise_sd,
        sigma_noise_on=sigma_noise_on,
        sigma_noise_sd=sigma_noise_sd,
    )

    # run simulation
    estimates_ds = sim_engine(*ics, estimates_ds)

    # add on other potentially observable quantities
    estimates_ds["IR"] = estimates_ds["R"] + estimates_ds["I"]
    if kind == "SEIR":
        estimates_ds["EI"] = estimates_ds["E"] + estimates_ds["I"]
        estimates_ds["EIR"] = estimates_ds["EI"] + estimates_ds["R"]

    # get minimum S for each simulation
    # at end and when the last policy turns on
    estimates_ds["S_min"] = estimates_ds.S.isel(t=-1)
    p3_on = (policies.policy_timeseries > 0).argmax(dim="t").max(dim="policy")
    estimates_ds["S_min_p3"] = estimates_ds.S.isel(t=p3_on)

    # blend in policy dataset
    estimates_ds = estimates_ds.merge(policies)

    # convert to daily observations
    daily_ds = adjust_timescales_to_daily(estimates_ds, tsteps_per_day)

    # prep regression LHS vars (logdiff)
    daily_ds["logdiff"] = (
        np.log(daily_ds[daily_ds.LHS.values])
        .diff(dim="t", n=1, label="lower")
        .pad(t=(0, 1))
        .to_array(dim="LHS")
    )
    if "sigma" not in daily_ds.logdiff.dims:
        daily_ds["logdiff"] = daily_ds.logdiff.expand_dims("sigma")

    # add noise
    daily_ds = add_obs_noise(
        daily_ds,
        measurement_noise_on=measurement_noise_on,
        measurement_noise_sd=measurement_noise_sd,
    )

    ## run regressions
    estimates = np.empty(
        (
            len(daily_ds.gamma),
            len(daily_ds.sigma),
            len(daily_ds.sample),
            len(daily_ds.LHS),
            len(daily_ds.policy) * len(reg_lag_days) + 1,
        ),
        dtype=np.float32,
    )
    mses = np.empty(
        (
            len(daily_ds.gamma),
            len(daily_ds.sigma),
            len(daily_ds.sample),
            len(daily_ds.LHS),
        ),
        dtype=np.float32,
    )
    estimates.fill(np.nan)
    mses.fill(np.nan)

    # add on lags
    RHS_old = (daily_ds.policy_timeseries > 0).astype(int)
    RHS_ds = xr.ones_like(RHS_old.isel(policy=0))
    RHS_ds["policy"] = "Intercept"
    for l in reg_lag_days:
        lag_vars = RHS_old.shift(t=l, fill_value=0)
        lag_vars["policy"] = [f"{x}_lag{l}" for x in RHS_old.policy.values]
        RHS_ds = xr.concat((RHS_ds, lag_vars), dim="policy")

    # Apply min cum_cases threshold used in regressions
    valid_reg = daily_ds.IR >= min_cases / pop
    if "sigma" not in valid_reg.dims:
        valid_reg = valid_reg.expand_dims("sigma")
        valid_reg["sigma"] = [np.nan]

    # only run regression on planned start day if we have at least one "no-policy" day after that
    # otherwise, start regression 2 days before first policy
    any_pol = (RHS_old > 0).max(dim="policy")
    first_pol = any_pol.argmax(dim="t")
    no_pol_on_regday0 = first_pol > valid_reg.argmax(dim="t")

    backup = any_pol.shift({"t": -2}).astype(bool)
    backup = backup | backup.isnull()

    # find random last day to end regression, starting with 1 day after last policy
    # is implemented
    if random_end:
        last_pol = (daily_ds.policy_timeseries.sum(dim="policy") == 3).argmax(dim="t")
        last_reg_day = (
            ((daily_ds.dims["t"] - (last_pol + 1)) * daily_ds.random_end)
            .round()
            .astype(int)
            + last_pol
            + 1
        )
    else:
        last_reg_day = daily_ds.dims["t"]
    daily_ds["random_end"] = last_reg_day

    # loop through regressions
    for cx, case_var in enumerate(daily_ds.LHS.values):
        case_ds = daily_ds.logdiff_stoch.sel(LHS=case_var)
        for gx, g in enumerate(daily_ds.gamma.values):
            g_ds = case_ds.sel(gamma=g)
            for sx, s in enumerate(daily_ds.sigma.values):
                s_ds = g_ds.sel(sigma=s)
                for samp in daily_ds.sample.values:
                    if no_pol_on_regday0.isel(sample=samp, gamma=gx, sigma=sx):
                        this_valid = valid_reg.isel(sample=samp, gamma=gx, sigma=sx)
                    else:
                        this_valid = backup.isel(sample=samp)
                    if random_end:
                        this_valid = (this_valid) & (RHS_ds.t <= last_reg_day[samp])
                    LHS = s_ds.isel(sample=samp)[this_valid].values
                    RHS = add_constant(
                        RHS_ds.isel(sample=samp)[{"t": this_valid}].values
                    )
                    res = OLS(LHS, RHS, missing="drop").fit()

                    estimates[gx, sx, samp, cx] = res.params
                    mses[gx, sx, samp, cx] = res.mse_resid
    coords = OrderedDict(
        gamma=daily_ds.gamma,
        sigma=daily_ds.sigma,
        sample=daily_ds.sample,
        LHS=daily_ds.LHS,
    )
    rmse_ds = xr.DataArray(np.sqrt(mses), coords=coords, dims=coords.keys())

    coords["policy"] = RHS_ds.policy
    e = xr.DataArray(estimates, coords=coords, dims=coords.keys()).to_dataset("policy")

    coeffs = []
    for p in daily_ds.policy.values:
        keys = [i for i in e.variables.keys() if f"{p}_" in i]
        coeffs.append(
            e[keys]
            .rename({k: int(k.split("_")[-1][3:]) for k in keys})
            .to_array(dim="reg_lag")
        )
    coef_ds = xr.concat(coeffs, dim="policy")
    coef_ds.name = "coefficient"
    daily_ds = daily_ds.drop("coefficient").merge(coef_ds)
    daily_ds["Intercept"] = e["Intercept"]
    daily_ds["rmse"] = rmse_ds

    # add model params
    daily_ds.attrs = attrs

    if save_dir is not None:
        save_dir.mkdir(exist_ok=True, parents=True)
        fname = f"pop_{int(pop)}_lag_{'-'.join([str(s) for s in reg_lag_days])}.nc"
        daily_ds.to_netcdf(save_dir / fname)

    return daily_ds


def load_reg_results(res_dir):
    reg_ncs = [f for f in res_dir.iterdir() if f.name[0] != "."]
    pops = [int(f.name.split("_")[1]) for f in reg_ncs]
    reg_res = xr.concat(
        [xr.open_dataset(f) for f in reg_ncs], dim="pop", data_vars="different"
    )
    reg_res["pop"] = pops
    reg_res["t"] = reg_res.t.astype(int)
    reg_res = reg_res.sortby("pop")
    return reg_res
