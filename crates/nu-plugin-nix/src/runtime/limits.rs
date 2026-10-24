//! Pure traversal accounting shared by both conversion directions.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum LimitExceeded {
    Depth,
    Nodes,
}

pub(super) struct TraversalBudget {
    max_depth: usize,
    remaining: usize,
}

impl TraversalBudget {
    pub(super) fn new(max_depth: usize, max_nodes: usize) -> Self {
        Self {
            max_depth,
            remaining: max_nodes,
        }
    }

    pub(super) fn enter(&mut self, depth: usize) -> Result<(), LimitExceeded> {
        if depth >= self.max_depth {
            return Err(LimitExceeded::Depth);
        }
        if self.remaining == 0 {
            return Err(LimitExceeded::Nodes);
        }
        self.remaining -= 1;
        Ok(())
    }

    pub(super) fn ensure_children(&self, count: usize) -> Result<(), LimitExceeded> {
        if count > self.remaining {
            Err(LimitExceeded::Nodes)
        } else {
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{LimitExceeded, TraversalBudget};

    #[test]
    fn depth_limit_is_exclusive() {
        let mut budget = TraversalBudget::new(2, 3);
        assert_eq!(budget.enter(0), Ok(()));
        assert_eq!(budget.enter(1), Ok(()));
        assert_eq!(budget.enter(2), Err(LimitExceeded::Depth));
    }

    #[test]
    fn every_enter_consumes_one_node() {
        let mut budget = TraversalBudget::new(4, 2);
        assert_eq!(budget.enter(0), Ok(()));
        assert_eq!(budget.enter(1), Ok(()));
        assert_eq!(budget.enter(1), Err(LimitExceeded::Nodes));
    }

    #[test]
    fn child_preflight_does_not_consume_budget() {
        let mut budget = TraversalBudget::new(4, 2);
        assert_eq!(budget.ensure_children(2), Ok(()));
        assert_eq!(budget.enter(0), Ok(()));
        assert_eq!(budget.ensure_children(2), Err(LimitExceeded::Nodes));
    }
}
