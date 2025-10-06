export const ilog2ceil = (n: number) => {
    let log = 0;
    n -= 1;
    while (n > 0) {
        n >>>= 1;
        log++;
    }
    return log;
};