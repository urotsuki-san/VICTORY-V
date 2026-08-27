from __future__ import annotations

import random
import unittest

from victory_v.euclid import EuclidPlane, VoronoiAtlas, reference_nearest


class EuclidPlaneTests(unittest.TestCase):
    def test_fence_can_finish_before_full_distance(self) -> None:
        points = ((1, 0, 0, 0), (100, 0, 0, 0), (120, 0, 0, 0))
        result = EuclidPlane(seed=7).nearest((0, 0, 0, 0), points)

        self.assertEqual(result.winner, 0)
        self.assertTrue(result.decision_exact)
        self.assertFalse(result.cache_hit)
        self.assertLess(result.grown_terms, result.total_terms)
        self.assertEqual(result.axis_order[0], 0)
        debts = [step.proof_debt for step in result.trace]
        self.assertEqual(debts, sorted(debts, reverse=True))

    def test_atlas_reuses_an_exact_voronoi_cell(self) -> None:
        atlas = VoronoiAtlas()
        plane = EuclidPlane(atlas=atlas, seed=3)
        points = ((0, 0), (10, 0), (0, 10))

        first = plane.nearest((0, 0), points)
        second = plane.nearest((1, 1), points)

        self.assertEqual(first.winner, 0)
        self.assertEqual(second.winner, 0)
        self.assertTrue(second.cache_hit)
        self.assertEqual(second.grown_terms, 0)
        self.assertEqual(len(atlas), 1)

    def test_atlas_does_not_cross_a_voronoi_boundary(self) -> None:
        atlas = VoronoiAtlas()
        plane = EuclidPlane(atlas=atlas)
        points = ((0, 0), (10, 0))

        plane.nearest((0, 0), points)
        other_side = plane.nearest((9, 0), points)
        repeated = plane.nearest((8, 0), points)

        self.assertEqual(other_side.winner, 1)
        self.assertFalse(other_side.cache_hit)
        self.assertEqual(repeated.winner, 1)
        self.assertTrue(repeated.cache_hit)

    def test_boundary_ties_choose_the_lower_candidate_index(self) -> None:
        atlas = VoronoiAtlas()
        plane = EuclidPlane(atlas=atlas)
        points = ((0, 0), (2, 0))

        first = plane.nearest((1, 0), points)
        second = plane.nearest((1, 0), points)

        self.assertEqual(first.winner, 0)
        self.assertEqual(second.winner, 0)
        self.assertTrue(second.cache_hit)

    def test_duplicate_points_are_tie_safe(self) -> None:
        points = ((3, -4), (3, -4), (100, 100))
        result = EuclidPlane().nearest((0, 0), points)
        self.assertEqual(result.winner, 0)

    def test_fog_seed_changes_only_the_schedule(self) -> None:
        points = ((2, 9, 4, 7), (8, 1, 5, 6), (6, 6, 6, 6))
        query = (4, 5, 3, 2)
        expected = reference_nearest(query, points)

        results = [EuclidPlane(seed=seed, fog_probes=7).nearest(query, points) for seed in range(8)]
        self.assertTrue(all(result.winner == expected for result in results))
        self.assertTrue(all(result.decision_exact for result in results))

    def test_random_jobs_match_full_precision_reference(self) -> None:
        rng = random.Random(8848)
        for _ in range(250):
            dimensions = rng.randint(1, 8)
            candidate_count = rng.randint(1, 9)
            query = tuple(rng.randint(-30, 30) for _ in range(dimensions))
            points = tuple(
                tuple(rng.randint(-30, 30) for _ in range(dimensions)) for _ in range(candidate_count)
            )
            result = EuclidPlane(seed=rng.randrange(1 << 30)).nearest(query, points)
            self.assertEqual(result.winner, reference_nearest(query, points))

    def test_supplied_bounds_are_checked(self) -> None:
        plane = EuclidPlane()
        with self.assertRaises(ValueError):
            plane.nearest((0, 0), ((1, 1),), coordinate_bounds=((-1, 1),))
        with self.assertRaises(ValueError):
            plane.nearest((0, 0), ((2, 1),), coordinate_bounds=((-1, 1), (-1, 1)))


if __name__ == "__main__":
    unittest.main()
