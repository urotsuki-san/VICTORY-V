"""Executable sketch of the VICTORY-V Euclid Plane.

The fog chooses which part of a geometric job to inspect first.  The fence
keeps exact lower and upper bounds.  A result is returned only after the
bounds prove it, or after an exact Atlas half-space guard matches.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from hashlib import blake2b
from random import Random
from typing import Sequence, TypeAlias

Point: TypeAlias = tuple[int, ...]
CoordinateBounds: TypeAlias = tuple[tuple[int, int], ...]


def _point(values: Sequence[int]) -> Point:
    return tuple(int(value) for value in values)


def _normalise_job(query: Sequence[int], points: Sequence[Sequence[int]]) -> tuple[Point, tuple[Point, ...]]:
    normal_query = _point(query)
    normal_points = tuple(_point(point) for point in points)
    if not normal_points:
        raise ValueError("a Euclid search needs at least one candidate point")
    if not normal_query:
        raise ValueError("zero-dimensional points are not supported")
    if any(len(point) != len(normal_query) for point in normal_points):
        raise ValueError("query and candidate points must have the same dimension")
    return normal_query, normal_points


def _feed_int(hasher: object, value: int) -> None:
    magnitude = abs(value)
    width = max(1, (magnitude.bit_length() + 7) // 8)
    hasher.update(bytes((1 if value < 0 else 0,)))
    hasher.update(width.to_bytes(2, "little"))
    hasher.update(magnitude.to_bytes(width, "little"))


def point_set_id(points: Sequence[Sequence[int]]) -> str:
    """Return a stable ID for an ordered candidate set."""

    normal_points = tuple(_point(point) for point in points)
    hasher = blake2b(digest_size=16, person=b"VICTORY-EUCLID")
    hasher.update(len(normal_points).to_bytes(4, "little"))
    for point in normal_points:
        hasher.update(len(point).to_bytes(2, "little"))
        for value in point:
            _feed_int(hasher, value)
    return hasher.hexdigest()


def squared_distance(left: Sequence[int], right: Sequence[int]) -> int:
    if len(left) != len(right):
        raise ValueError("distance operands must have the same dimension")
    return sum((int(a) - int(b)) ** 2 for a, b in zip(left, right, strict=True))


def reference_nearest(query: Sequence[int], points: Sequence[Sequence[int]]) -> int:
    normal_query, normal_points = _normalise_job(query, points)
    return min(
        range(len(normal_points)),
        key=lambda index: (squared_distance(normal_query, normal_points[index]), index),
    )


@dataclass(frozen=True, slots=True)
class HalfSpace:
    """One exact face of a tie-aware Voronoi cell."""

    normal: Point
    limit: int
    inclusive: bool

    def contains(self, query: Point) -> bool:
        value = sum(coefficient * coordinate for coefficient, coordinate in zip(self.normal, query, strict=True))
        return value <= self.limit if self.inclusive else value < self.limit


@dataclass(frozen=True, slots=True)
class VoronoiCell:
    point_set: str
    winner: int
    faces: tuple[HalfSpace, ...]
    route: tuple[int, ...]

    def contains(self, query: Point) -> bool:
        return all(face.contains(query) for face in self.faces)


class VoronoiAtlas:
    """A guarded decision cache.

    Entries cache regions, not guessed values.  A hit is exact because every
    stored half-space is checked before the winner is returned.
    """

    def __init__(self, capacity: int = 32) -> None:
        if capacity < 1:
            raise ValueError("Atlas capacity must be positive")
        self.capacity = capacity
        self._cells: list[VoronoiCell] = []

    def __len__(self) -> int:
        return len(self._cells)

    def lookup(self, dataset: str, query: Point) -> VoronoiCell | None:
        for offset in range(len(self._cells) - 1, -1, -1):
            cell = self._cells[offset]
            if cell.point_set == dataset and cell.contains(query):
                if offset != len(self._cells) - 1:
                    self._cells.append(self._cells.pop(offset))
                return cell
        return None

    def route_hint(self, dataset: str) -> tuple[int, ...]:
        for cell in reversed(self._cells):
            if cell.point_set == dataset:
                return cell.route
        return ()

    def remember(self, points: tuple[Point, ...], winner: int, route: tuple[int, ...]) -> None:
        dataset = point_set_id(points)
        winner_point = points[winner]
        winner_norm = sum(value * value for value in winner_point)
        faces: list[HalfSpace] = []

        for other_index, other_point in enumerate(points):
            if other_index == winner:
                continue
            normal = tuple(2 * (other - selected) for selected, other in zip(winner_point, other_point, strict=True))
            limit = sum(value * value for value in other_point) - winner_norm
            faces.append(HalfSpace(normal=normal, limit=limit, inclusive=winner < other_index))

        self._cells = [
            cell for cell in self._cells if not (cell.point_set == dataset and cell.winner == winner)
        ]
        self._cells.append(VoronoiCell(dataset, winner, tuple(faces), route))
        if len(self._cells) > self.capacity:
            del self._cells[0 : len(self._cells) - self.capacity]


@dataclass(slots=True)
class _DistanceBud:
    query: Point
    point: Point
    ceilings: tuple[int, ...]
    known_axes: int = 0
    lower: int = 0
    remaining: int = 0

    def __post_init__(self) -> None:
        self.remaining = sum(self.ceilings)

    @property
    def upper(self) -> int:
        return self.lower + self.remaining

    @property
    def debt(self) -> int:
        return self.upper - self.lower

    def refine(self, axis: int) -> bool:
        mask = 1 << axis
        if self.known_axes & mask:
            return False
        exact_term = (self.query[axis] - self.point[axis]) ** 2
        ceiling = self.ceilings[axis]
        if exact_term > ceiling:
            raise RuntimeError("invalid Euclid ceiling")
        self.known_axes |= mask
        self.lower += exact_term
        self.remaining -= ceiling
        return True


@dataclass(frozen=True, slots=True)
class GrowthStep:
    generation: int
    axis: int
    draft_leader: int
    proof_debt: int
    bounds: tuple[tuple[int, int], ...]


@dataclass(frozen=True, slots=True)
class SearchResult:
    winner: int
    decision_exact: bool
    cache_hit: bool
    proof_kind: str
    grown_terms: int
    total_terms: int
    generations: int
    distance_bounds: tuple[int, int] | None
    draft_votes: tuple[int, ...]
    axis_order: tuple[int, ...]
    trace: tuple[GrowthStep, ...]


class EuclidPlane:
    """Proof-directed nearest-neighbour model for the first Euclid experiment."""

    def __init__(
        self,
        *,
        atlas: VoronoiAtlas | None = None,
        fog_probes: int = 4,
        fog_width: int = 2,
        fog_bits: int = 4,
        seed: int = 0,
    ) -> None:
        if fog_probes < 0:
            raise ValueError("fog_probes cannot be negative")
        if fog_width < 1:
            raise ValueError("fog_width must be positive")
        if fog_bits < 1:
            raise ValueError("fog_bits must be positive")
        self.atlas = atlas if atlas is not None else VoronoiAtlas()
        self.fog_probes = fog_probes
        self.fog_width = fog_width
        self.fog_bits = fog_bits
        self.seed = seed

    def nearest(
        self,
        query: Sequence[int],
        points: Sequence[Sequence[int]],
        *,
        coordinate_bounds: Sequence[tuple[int, int]] | None = None,
        seed: int | None = None,
    ) -> SearchResult:
        normal_query, normal_points = _normalise_job(query, points)
        dataset = point_set_id(normal_points)
        total_terms = len(normal_points) * len(normal_query)

        cached = self.atlas.lookup(dataset, normal_query)
        if cached is not None:
            return SearchResult(
                winner=cached.winner,
                decision_exact=True,
                cache_hit=True,
                proof_kind="atlas-halfspace",
                grown_terms=0,
                total_terms=total_terms,
                generations=0,
                distance_bounds=None,
                draft_votes=tuple(0 for _ in normal_points),
                axis_order=cached.route,
                trace=(),
            )

        bounds = self._coordinate_bounds(normal_query, normal_points, coordinate_bounds)
        ceilings = tuple((high - low) ** 2 for low, high in bounds)
        rng = Random(self.seed if seed is None else seed)
        votes, axis_order = self._fog_schedule(normal_query, normal_points, bounds, dataset, rng)
        buds = [_DistanceBud(normal_query, point, ceilings) for point in normal_points]

        winner = self._proven_winner(buds)
        if winner is not None:
            self.atlas.remember(normal_points, winner, ())
            return SearchResult(
                winner=winner,
                decision_exact=True,
                cache_hit=False,
                proof_kind="fence",
                grown_terms=0,
                total_terms=total_terms,
                generations=0,
                distance_bounds=(buds[winner].lower, buds[winner].upper),
                draft_votes=votes,
                axis_order=axis_order,
                trace=(),
            )

        trace: list[GrowthStep] = []
        grown_terms = 0
        winner = None
        used_route: list[int] = []

        for generation, axis in enumerate(axis_order, start=1):
            used_route.append(axis)
            for bud in buds:
                if bud.refine(axis):
                    grown_terms += 1

            leader = min(
                range(len(buds)),
                key=lambda index: (
                    buds[index].lower + buds[index].upper,
                    -votes[index],
                    index,
                ),
            )
            winner = self._proven_winner(buds)
            trace.append(
                GrowthStep(
                    generation=generation,
                    axis=axis,
                    draft_leader=leader,
                    proof_debt=sum(bud.debt for bud in buds),
                    bounds=tuple((bud.lower, bud.upper) for bud in buds),
                )
            )
            if winner is not None:
                break

        if winner is None:
            raise RuntimeError("Euclid search exhausted its axes without a proof")

        route = tuple(used_route)
        self.atlas.remember(normal_points, winner, route)
        return SearchResult(
            winner=winner,
            decision_exact=True,
            cache_hit=False,
            proof_kind="fence",
            grown_terms=grown_terms,
            total_terms=total_terms,
            generations=len(trace),
            distance_bounds=(buds[winner].lower, buds[winner].upper),
            draft_votes=votes,
            axis_order=axis_order,
            trace=tuple(trace),
        )

    @staticmethod
    def _coordinate_bounds(
        query: Point,
        points: tuple[Point, ...],
        supplied: Sequence[tuple[int, int]] | None,
    ) -> CoordinateBounds:
        if supplied is None:
            return tuple(
                (
                    min((query[axis], *(point[axis] for point in points))),
                    max((query[axis], *(point[axis] for point in points))),
                )
                for axis in range(len(query))
            )

        bounds = tuple((int(low), int(high)) for low, high in supplied)
        if len(bounds) != len(query):
            raise ValueError("coordinate bounds must match the point dimension")
        for axis, (low, high) in enumerate(bounds):
            if low > high:
                raise ValueError("coordinate bounds cannot be inverted")
            if not low <= query[axis] <= high:
                raise ValueError("query lies outside the supplied coordinate bounds")
            if any(not low <= point[axis] <= high for point in points):
                raise ValueError("a candidate lies outside the supplied coordinate bounds")
        return bounds

    def _fog_schedule(
        self,
        query: Point,
        points: tuple[Point, ...],
        bounds: CoordinateBounds,
        dataset: str,
        rng: Random,
    ) -> tuple[tuple[int, ...], tuple[int, ...]]:
        dimensions = len(query)
        width = max(1, max((high - low).bit_length() for low, high in bounds))
        shift = max(0, width - self.fog_bits)
        coarse: list[list[int]] = []
        for axis in range(dimensions):
            axis_terms = []
            for point in points:
                delta = abs(query[axis] - point[axis])
                prefix = delta >> shift
                axis_terms.append(prefix * prefix)
            coarse.append(axis_terms)

        votes = [0 for _ in points]
        support: Counter[int] = Counter()
        probe_width = min(self.fog_width, dimensions)
        for _ in range(self.fog_probes):
            axes = tuple(rng.sample(range(dimensions), probe_width))
            support.update(axes)
            winner = min(
                range(len(points)),
                key=lambda index: (sum(coarse[axis][index] for axis in axes), index),
            )
            votes[winner] += 1

        hint = self.atlas.route_hint(dataset)
        hinted = tuple(axis for axis in hint if 0 <= axis < dimensions)
        used = set(hinted)
        remaining = [axis for axis in range(dimensions) if axis not in used]
        jitter = {axis: rng.random() for axis in remaining}
        remaining.sort(
            key=lambda axis: (
                support[axis],
                max(coarse[axis]) - min(coarse[axis]),
                jitter[axis],
            ),
            reverse=True,
        )
        return tuple(votes), hinted + tuple(remaining)

    @staticmethod
    def _proven_winner(buds: Sequence[_DistanceBud]) -> int | None:
        for candidate, bud in enumerate(buds):
            winner_upper = bud.upper
            for rival, rival_bud in enumerate(buds):
                if rival == candidate:
                    continue
                if candidate < rival:
                    if winner_upper > rival_bud.lower:
                        break
                elif winner_upper >= rival_bud.lower:
                    break
            else:
                return candidate
        return None
