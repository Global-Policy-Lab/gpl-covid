import xarray as xr
import matplotlib.pyplot as plt
import numpy as np
import warnings


def facet_hist(estimates, case_type, coef, n_bins=40, hist_kwargs = {}, **kwargs):
    true_vals = {
        "Intercept": estimates.attrs["no_policy_growth_rate"],
        "p1": estimates.attrs["p1_effect"],
        "p2": estimates.attrs["p2_effect"],
        "p3": estimates.attrs["p3_effect"],
    }
    true_vals["cum_effect"] = true_vals["p1"] + true_vals["p2"] + true_vals["p3"]
    if true_vals[coef] > 0:
        min_bin = 0
        max_bin = true_vals[coef] * 2
    elif true_vals[coef] < 0:
        min_bin = true_vals[coef] * 2
        max_bin = 0
    g = xr.plot.FacetGrid(estimates.sel(case_type=case_type), **kwargs)
    for ax in g.axes.flat:
        ax.axvline(true_vals[coef], color="k", label="True")
        ax.set_xlim(min_bin, max_bin)
    def nowarn_hist(*args, **kwargs):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            return plt.hist(*args, **kwargs)

    g.map(nowarn_hist, coef, bins=np.linspace(min_bin, max_bin, n_bins), **hist_kwargs)
    g.map(
        lambda x: plt.axvline(
            np.nanmedian(x), color="r", linestyle="--", label="Median\nestimate"
        ),
        coef,
    )
    g.map(
        lambda x, y: plt.text(
            0.97,
            0.97,
            f"$min(S)$: {x.min().item():.2f}\n$min(S)_{{p3}}$: {y.min().item():.2f}",
            horizontalalignment="right",
            verticalalignment="top",
            transform=plt.gca().transAxes,
        ),
        "S_min",
        "S_min_p3",
    )
    g.axes.flat[0].legend(loc="upper left")
    g.set_xlabels("")
    g.set_titles("$\{coord}$ = {value}")
    g.fig.suptitle(f"LHS: {case_type}; variable: {coef}", va="bottom", y=0.99)
    return g
