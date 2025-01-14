// Copyright (C) 2022 setzer22 and contributors
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

use std::ops::Index;

use super::node_graph::Graph;

use crate::prelude::*;
use blackjack_engine::graph_compiler::ExternalParameterValues;
use blackjack_engine::{
    graph::{BjkGraph, BjkNodeId},
    graph_compiler::CompiledProgram,
};
use egui_node_graph::{InputId, NodeId, OutputId};
use slotmap::SecondaryMap;

#[derive(Clone, Debug)]
pub struct NodeMapping(
    SecondaryMap<NodeId, BjkNodeId>,
    SecondaryMap<BjkNodeId, NodeId>,
);
impl Index<NodeId> for NodeMapping {
    type Output = BjkNodeId;
    fn index(&self, index: NodeId) -> &Self::Output {
        &self.0[index]
    }
}
impl Index<BjkNodeId> for NodeMapping {
    type Output = NodeId;
    fn index(&self, index: BjkNodeId) -> &Self::Output {
        &self.1[index]
    }
}

pub fn ui_graph_to_blackjack_graph(graph: &Graph) -> Result<(BjkGraph, NodeMapping)> {
    let mut bjk_graph = BjkGraph::new();
    let mut mapping = SecondaryMap::<NodeId, BjkNodeId>::new();
    let mut rev_mapping = SecondaryMap::<BjkNodeId, NodeId>::new();
    let mut input_names = SecondaryMap::<InputId, &str>::new();
    let mut output_names = SecondaryMap::<OutputId, &str>::new();

    for (node_id, node) in &graph.nodes {
        let bjk_id = bjk_graph.add_node(
            node.user_data.op_name.clone(),
            node.user_data.returns.clone(),
        );
        mapping.insert(node_id, bjk_id);
        rev_mapping.insert(bjk_id, node_id);

        for (input_name, input_id) in &node.inputs {
            bjk_graph.add_input(bjk_id, input_name, graph.inputs[*input_id].typ.0)?;
            input_names.insert(*input_id, input_name);
        }
        for (output_name, output_id) in &node.outputs {
            bjk_graph.add_output(bjk_id, output_name, graph.outputs[*output_id].typ.0)?;
            output_names.insert(*output_id, output_name);
        }
    }

    for (input, output) in &graph.connections {
        let input_name = input_names[input];
        let output_name = output_names[*output];

        let input_node_id = mapping[graph[input].node];
        let output_node_id = mapping[graph[*output].node];

        bjk_graph.add_connection(output_node_id, output_name, input_node_id, input_name)?;
    }

    Ok((bjk_graph, NodeMapping(mapping, rev_mapping)))
}

pub fn extract_graph_params(
    graph: &Graph,
    mapping: &NodeMapping,
    program: &CompiledProgram,
) -> Result<ExternalParameterValues> {
    let mut params = ExternalParameterValues::default();

    for external_def in &program.external_parameters {
        let node = mapping[external_def.node_id];
        let input = graph[node].get_input(&external_def.param_name)?;
        // TODO: @perf The whole parameter definition is copied here, but we're
        // just interested in the data table that we'll feed into Lua. Maybe we
        // need two different concepts here?
        params.insert(external_def.addr.clone(), graph[input].value.0.clone());
    }

    Ok(params)
}
