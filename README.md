# ksync-test

This repository contains a test for [Ksync](https://github.com/ksync/ksync) running on [Minikube](https://github.com/kubernetes/minikube).

## Usage

The test consists of a bunch of iterations, looping:

- from `minDirsCount` to `maxDirsCount` directories to sync (respectively defaulting to 2 and 5)
- from `minFilesCount` to `maxFilesCount` files to sync in each directory (respectively defaulting to 8 and 10)
- from `minJobsCount` to `maxJobsCount` jobs, where reside the containers in which each directory has to be synced with (respectively defaulting to 1 and 3)

Each iteration:

- Set up Minikube on a clean base
- Set up Ksync on a clean base
- Has a timeout after which the iteration is considered done: `activeDeadlineSeconds`

The Minikube cluster configuration can be adjusted on top of the `index.sh` file before running the script.

To launch the test, run:

```sh
chmod +x ./index.sh && ./index.sh "${activeDeadlineSeconds:-"180"}" "${minDirsCount:-"2"}" "${maxDirsCount:-"5"}" "${minFilesCount:-"8"}" "${maxFilesCount:-"10"}" "${minJobsCount:-"2"}" "${maxJobsCount:-"5"}"
```

## Results

The results of the test running with the above-mentioned defaults are those versioned in this repository.

## Interpretations
