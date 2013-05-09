package com.puppetlabs.gatling.config

import scala.util.parsing.json.JSON
import com.puppetlabs.json.{JsonInt, JsonList, JsonString, JsonMap}
import com.puppetlabs.gatling.simulation.SimulationWithScenario

class PuppetGatlingConfig(configFilePath: String) {

  private val Some(JsonMap(config)) = JSON.parseFull(io.Source.fromFile(configFilePath).mkString)

  private val JsonList(jsonNodes) = config("nodes")

  val JsonString(simulationId) = config("simulation_id")
  val JsonString(runDescription) = config("run_description")
  val JsonString(baseUrl) = config("base_url")

  val nodes = jsonNodes.map((n) => {
    val JsonMap(node) = n
    val JsonString(simClass) = node("simulation_class")
    val JsonInt(numInstances) = node("num_instances")
    val JsonInt(numRepetitions) = node("num_repetitions")
    val JsonInt(rampUpDuration) = node("ramp_up_duration_seconds")
    Node(Class.forName(simClass).asInstanceOf[Class[SimulationWithScenario]], numRepetitions, numInstances, rampUpDuration)
  })
}


object PuppetGatlingConfig {
  def apply(configFilePath: String) = new PuppetGatlingConfig(configFilePath)

  private var instance: Option[PuppetGatlingConfig] = None

  def initialize(configFilePath: String): PuppetGatlingConfig = {
    instance = Some(PuppetGatlingConfig(configFilePath))
    instance.get
  }

  def configuration: PuppetGatlingConfig = {
    instance match {
      case None => throw new IllegalStateException("Configuration not yet initialized; please call #initialize method!")
      case _ => instance.get
    }
  }

}
