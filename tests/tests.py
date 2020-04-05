def test_readme():
    with open("README.md", "r") as f:
        readme = f.read()
    with open("run", "r") as f:
        for l in f:
            for prog in ["python", "Rscript", "stata"]:
                # skip quality check, which is not in readme
                if l.startswith(prog) and "quality-check-processed-datasets" not in l:
                    tocomp = l.rstrip("\n")
                    assert tocomp in readme, tocomp
