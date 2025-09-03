optimism_package = import_module("github.com/ethpandaops/optimism-package/main.star")

def run(plan, args):
    # Load local simple.yaml config
    # just delegate to optimism-package with local args
    optimism_package.run(plan, args)
