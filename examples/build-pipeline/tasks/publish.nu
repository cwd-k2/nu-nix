let destination = $env.NU_NIX_PIPELINE_PUBLISHED
mkdir ($destination | path dirname)

open $env.NU_NIX_PIPELINE_REPORT
| insert published true
| to json --indent 2
| save --force $destination

print $"published ($destination)"
