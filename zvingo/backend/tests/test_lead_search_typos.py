"""Search must actually tolerate typos, not just claim to.

`GET /catalog/search` documents itself as "typo-tolerant search". The Python
ranker genuinely is -- it scores near-misses with difflib above a threshold.
But the ranker only ever sees the candidates the Mongo pre-filter returned, and
that pre-filter was an exact substring regex. A misspelling is not a substring
of the correct word, so the pool came back empty and there was nothing for the
ranker to rescue: searching "sadza" found the restaurant, "sadsa" found nothing.

Found by running the server and typing a typo, not by unit tests -- the ranker's
own tests pass it a pool directly, so they never exercised the pre-filter.
"""

import re

from app.catalog.router import _candidate_query


def _matches(query: str, *fields: str) -> bool:
    """True if the candidate pre-filter would select a doc with these fields."""
    clauses = _candidate_query(query)["$or"]
    for clause in clauses:
        for value in clause.values():
            pattern = value["$regex"]
            if any(re.search(pattern, f, re.I) for f in fields):
                return True
    return False


MENU = ("Kombi Cafe", "Sadza & Beef Stew", "Grilled Chicken & Chips")


def test_an_exact_term_still_matches():
    assert _matches("sadza", *MENU)
    assert _matches("chicken", *MENU)
    assert _matches("kombi", *MENU)


def test_a_substituted_letter_still_reaches_the_ranker():
    assert _matches("sadsa", *MENU), "sadsa should still select the Sadza dish"
    assert _matches("kombe", *MENU)


def test_a_dropped_letter_still_reaches_the_ranker():
    assert _matches("chiken", *MENU)
    assert _matches("chikn", *MENU)


def test_the_stem_anchors_to_a_word_not_the_start_of_the_field():
    """These fields hold phrases; the searched word is rarely the first one.

    Anchoring with ^ matched "Sadza & Beef Stew" but not the "Chicken" inside
    "Grilled Chicken & Chips".
    """
    assert _matches("chiken", "Grilled Chicken & Chips")


def test_an_unrelated_term_is_not_dragged_in():
    """Widening recall must not turn search into a firehose."""
    assert not _matches("pizza", *MENU)
    assert not _matches("sushi", *MENU)
    assert not _matches("burger", *MENU)


def test_a_short_token_is_not_stemmed():
    """Stemming a 3-letter token would match almost everything."""
    clauses = _candidate_query("tea")["$or"]
    patterns = {v["$regex"] for c in clauses for v in c.values()}
    assert patterns == {"tea"}
