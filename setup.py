from setuptools import find_namespace_packages, setup

setup(
    name="src",
    package_dir={"": "code"},
    packages=find_namespace_packages(where="code"),
    version="0.1.0",
    description="Estimating the impact of COVID policy on disease spread",
    author="Global Policy Lab",
    license="MIT",
)
