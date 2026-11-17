#include "rubik.h"
#include "rubik_tables.h"

/* Optimal 2x2x2 solver: iterative deepening that ends in a lookup table.
 *
 * A state is two ranks: p, the Lehmer rank of the seven cubie places
 * (0..5039), and o, the base-3 number of the first six twists (0..728); the
 * seventh twist follows from the other six. Solved is p = o = 0. A quarter turn
 * of face f maps them through rubik_pn[f][p] and rubik_on[f][o], so the search
 * never rebuilds a cube, and never divides.
 *
 * rubik_near[] holds every state within 5 moves of solved with its distance,
 * sorted by key = (p << 10) | o, and rubik_far[] every state at distance 11.
 * Then:
 *   1. A state in near[] is solved by walking down the table: some move
 *      always leads to a state one move closer.
 *   2. Otherwise the distance d is at least 6. For bound = 6, 7, ... a
 *      depth-first search makes bound - 5 moves and asks near[] whether the
 *      state reached is within 5 moves; the first bound that succeeds is d,
 *      because every smaller bound failed.
 *   3. A state in far[] is at distance 11. One move to a neighbor that is not
 *      in far[] reaches distance 10, which skips the search of bound 11, the
 *      most expensive one.
 * See gen_tables.py for how the tables are made.
 */

enum { CUBIES = 7, MAX_MOVES = 11, NEAR_DEPTH = 5, NO_FACE = 3 };

#define KEY(p, o) (((uint32_t) (p) << 10) | (uint32_t) (o))

/* Parse and validate the 14-character state into cubie places p[] and twists
 * o[], both 0-based. Returns 0 when the state is valid, -1 otherwise.
 */
static int parse_state(const char *state, uint8_t p[CUBIES], uint8_t o[CUBIES])
{
    /* Exactly 14 characters. Stop at the first NUL, so a short string is
     * never read past its end.
     */
    for (int i = 0; i < RUBIK_STATE_LEN; i++) {
        if (state[i] == '\0')
            return -1;
    }
    if (state[RUBIK_STATE_LEN] != '\0')
        return -1;

    /* Places: '1'..'7', each exactly once. */
    uint8_t seen[CUBIES] = {0};
    for (int i = 0; i < CUBIES; i++) {
        char c = state[i];
        if (c < '1' || c > '7')
            return -1;
        int k = c - '1';
        if (seen[k])
            return -1;
        seen[k] = 1;
        p[i] = (uint8_t) k;
    }

    /* Twists: '1'..'3', and their values minus one sum to a multiple of 3.
     * The sum is at most 14, so subtracting 3 replaces the modulo.
     */
    int sum = 0;
    for (int i = 0; i < CUBIES; i++) {
        char c = state[CUBIES + i];
        if (c < '1' || c > '3')
            return -1;
        o[i] = (uint8_t) (c - '1');
        sum += o[i];
    }
    while (sum >= 3)
        sum -= 3;
    if (sum != 0)
        return -1;

    return 0;
}

/* Lehmer rank: for each place, how many later places hold a smaller cubie,
 * read as a mixed-radix number with digits of radix 7, 6, ..., 1.
 */
static uint32_t rank_perm(const uint8_t p[CUBIES])
{
    uint32_t r = 0;
    for (int i = 0; i < CUBIES; i++) {
        uint32_t smaller = 0;
        for (int j = i + 1; j < CUBIES; j++)
            smaller += p[j] < p[i];
        r = r * (uint32_t) (CUBIES - i) + smaller;
    }
    return r;
}

/* The first six twists as a base-3 number. */
static uint32_t rank_orient(const uint8_t o[CUBIES])
{
    uint32_t r = 0;
    for (int i = 0; i < CUBIES - 1; i++)
        r = r * 3 + o[i];
    return r;
}

/* Distance of key when it is within 5 moves of solved, else -1. */
static int near_dist(uint32_t key)
{
    uint32_t lo = 0, hi = RUBIK_NEAR;
    while (lo < hi) {
        uint32_t mid = (lo + hi) >> 1;
        uint32_t k = rubik_near[mid] >> 3;
        if (k == key)
            return (int) (rubik_near[mid] & 7);
        if (k < key)
            lo = mid + 1;
        else
            hi = mid;
    }
    return -1;
}

/* Whether key is at distance 11. */
static int is_far(uint32_t key)
{
    uint32_t lo = 0, hi = RUBIK_FAR;
    while (lo < hi) {
        uint32_t mid = (lo + hi) >> 1;
        uint32_t k = rubik_far[mid];
        if (k == key)
            return 1;
        if (k < key)
            lo = mid + 1;
        else
            hi = mid;
    }
    return 0;
}

struct search {
    uint8_t moves[MAX_MOVES]; /* move m = face * 3 + quarter turns - 1 */
    int len;                  /* moves made before the depth-first search */
    int limit;                /* depth at which near[] is asked */
    uint32_t p, o;            /* the state where near[] answered */
};

/* Make limit - depth more moves from (p, o), never turning the face of the
 * previous move again (two turns of one face are one move). Returns 1 when a
 * state within 5 moves of solved is reached at depth limit.
 */
static int dfs(struct search *s,
               uint32_t p,
               uint32_t o,
               int depth,
               int last_face)
{
    if (depth == s->limit) {
        if (near_dist(KEY(p, o)) < 0)
            return 0;
        s->p = p;
        s->o = o;
        return 1;
    }
    for (int f = 0; f < 3; f++) {
        if (f == last_face)
            continue;
        uint32_t q = p, t = o;
        for (int n = 0; n < 3; n++) {
            q = rubik_pn[f][q];
            t = rubik_on[f][t];
            s->moves[s->len + depth] = (uint8_t) (f * 3 + n);
            if (dfs(s, q, t, depth + 1, f))
                return 1;
        }
    }
    return 0;
}

/* Walk from (p, o), d moves from solved, down near[] to solved, appending
 * the moves.
 */
static void descend(struct search *s, uint32_t p, uint32_t o, int d)
{
    while (d > 0) {
        for (int f = 0; f < 3; f++) {
            uint32_t q = p, t = o;
            int n;
            for (n = 0; n < 3; n++) {
                q = rubik_pn[f][q];
                t = rubik_on[f][t];
                if (near_dist(KEY(q, t)) == d - 1)
                    break;
            }
            if (n < 3) {
                s->moves[s->len++] = (uint8_t) (f * 3 + n);
                p = q;
                o = t;
                d--;
                break;
            }
        }
    }
}

/* Write the moves as text: "R", "R2" or "R'" per move, single spaces. */
static int emit(const struct search *s, char *out, size_t cap)
{
    /* Indexed by the move, so no division by 3 is needed. */
    static const char face_name[9] = {'R', 'R', 'R', 'B', 'B',
                                      'B', 'D', 'D', 'D'};
    static const char suffix[9] = {'\0', '2',  '\'', '\0', '2',
                                   '\'', '\0', '2',  '\''};

    size_t need = 1; /* the NUL */
    for (int i = 0; i < s->len; i++)
        need += (i > 0) + 1 + (suffix[s->moves[i]] != '\0');
    if (need > cap) {
        if (cap >= 1)
            out[0] = '\0';
        return -2;
    }
    size_t k = 0;
    for (int i = 0; i < s->len; i++) {
        int m = s->moves[i];
        if (i > 0)
            out[k++] = ' ';
        out[k++] = face_name[m];
        if (suffix[m])
            out[k++] = suffix[m];
    }
    out[k] = '\0';
    return s->len;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    uint8_t cp[CUBIES], co[CUBIES];
    if (parse_state(state, cp, co) != 0)
        return -1;
    uint32_t p = rank_perm(cp), o = rank_orient(co);

    struct search s;
    s.len = 0;
    int first_face = NO_FACE;

    int d = near_dist(KEY(p, o));
    if (d >= 0) {
        descend(&s, p, o, d);
        return emit(&s, out, cap);
    }

    if (is_far(KEY(p, o))) {
        /* Every neighbor is at distance 10 or 11; take one at 10. */
        int done = 0;
        for (int f = 0; f < 3 && !done; f++) {
            uint32_t q = p, t = o;
            for (int n = 0; n < 3; n++) {
                q = rubik_pn[f][q];
                t = rubik_on[f][t];
                if (!is_far(KEY(q, t))) {
                    s.moves[s.len++] = (uint8_t) (f * 3 + n);
                    p = q;
                    o = t;
                    first_face = f;
                    done = 1;
                    break;
                }
            }
        }
    }

    for (int bound = NEAR_DEPTH + 1;; bound++) {
        s.limit = bound - NEAR_DEPTH;
        if (dfs(&s, p, o, 0, first_face))
            break;
    }
    s.len += s.limit;
    descend(&s, s.p, s.o, near_dist(KEY(s.p, s.o)));
    return emit(&s, out, cap);
}
