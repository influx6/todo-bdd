"""The executable specification for a todo list.

There is one of these. It runs against the domain service, the HTTP API and a
real browser without changing a character, because it never mentions any of
them. Read it as a description of what the product does; if it stops describing
the product, that is a bug in the product or a change of intent, never a test
to be patched.

Nothing here knows about ids, status codes, selectors or SQL. If you find
yourself wanting one of those, it belongs in a driver.

Each `a_todo_is_added` hands back a reference the test can name. Where a name
carries meaning from the conversation — `mondays_milk` versus `thursdays_milk`
— use it. Where there is only one todo in play, a plain name is clearer.
"""

from __future__ import annotations

from .dsl import done


class TestCapturingWork:
    def test_a_new_todo_appears_on_the_list(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")

        dsl.the_list_reads(milk)

    def test_todos_are_listed_oldest_first(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dsl.time_passes(minutes=5)
        dentist = dsl.a_todo_is_added("Call the dentist")

        dsl.the_list_reads(milk, dentist)

    def test_surrounding_whitespace_is_tidied_away(self, dsl):
        milk = dsl.a_todo_is_added_with_untidy_spacing("Buy milk")

        dsl.the_list_reads(milk)

    def test_a_todo_must_have_a_title(self, dsl):
        dsl.a_todo_is_added_with_no_title()

        dsl.the_message_shown_is("A todo needs a title")
        dsl.the_list_is_empty()

    def test_a_title_has_to_be_readable_at_a_glance(self, dsl):
        dsl.a_todo_is_added_with_an_overlong_title()

        dsl.the_message_shown_is("Keep the title under 120 characters")
        dsl.the_list_is_empty()

    def test_the_same_thing_is_not_added_twice(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")

        dsl.a_todo_is_added_expecting_refusal("Buy milk")

        dsl.the_message_shown_is("'Buy milk' is already on your list")
        dsl.the_list_reads(milk)


class TestGettingWorkDone:
    def test_completing_a_todo_marks_it_done(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")

        dsl.the_todo_is_completed(milk)

        dsl.the_list_reads(done(milk))
        dsl.no_message_is_shown()

    def test_finished_work_sinks_below_outstanding_work(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dentist = dsl.a_todo_is_added("Call the dentist")

        dsl.the_todo_is_completed(milk)

        dsl.the_list_reads(dentist, done(milk))

    def test_the_most_recently_finished_work_sits_at_the_top_of_the_done_pile(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dentist = dsl.a_todo_is_added("Call the dentist")

        dsl.the_todo_is_completed(milk)
        dsl.time_passes(hours=1)
        dsl.the_todo_is_completed(dentist)

        dsl.the_list_reads(done(dentist), done(milk))

    def test_finishing_something_frees_its_title_to_be_used_again(self, dsl):
        mondays_milk = dsl.a_todo_is_added("Buy milk")
        dsl.the_todo_is_completed(mondays_milk)

        thursdays_milk = dsl.a_todo_is_added("Buy milk")

        dsl.no_message_is_shown()
        dsl.the_list_reads(thursdays_milk, done(mondays_milk))

    def test_work_can_be_picked_back_up(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dsl.the_todo_is_completed(milk)

        dsl.the_todo_is_reopened(milk)

        dsl.the_list_reads(milk)

    def test_work_cannot_be_picked_back_up_onto_a_taken_title(self, dsl):
        mondays_milk = dsl.a_todo_is_added("Buy milk")
        dsl.the_todo_is_completed(mondays_milk)
        thursdays_milk = dsl.a_todo_is_added("Buy milk")

        dsl.the_todo_is_reopened(mondays_milk)

        dsl.the_message_shown_is("'Buy milk' is already back on your list")
        dsl.the_list_reads(thursdays_milk, done(mondays_milk))


class TestClearingThingsOut:
    def test_a_todo_can_be_thrown_away(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dentist = dsl.a_todo_is_added("Call the dentist")

        dsl.the_todo_is_deleted(milk)

        dsl.the_list_reads(dentist)

    def test_finished_work_can_be_thrown_away(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dsl.the_todo_is_completed(milk)

        dsl.the_todo_is_deleted(milk)

        dsl.the_list_is_empty()

    def test_only_the_named_todo_is_thrown_away_when_a_title_is_reused(self, dsl):
        mondays_milk = dsl.a_todo_is_added("Buy milk")
        dsl.the_todo_is_completed(mondays_milk)
        thursdays_milk = dsl.a_todo_is_added("Buy milk")

        dsl.the_todo_is_deleted(mondays_milk)

        dsl.the_list_reads(thursdays_milk)
