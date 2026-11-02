import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy
from scan_planner_msgs.msg import LocomotionState
class P(Node):
    def __init__(self):
        super().__init__('fake_locomotion')
        q=QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE, durability=DurabilityPolicy.TRANSIENT_LOCAL)
        self.pub=self.create_publisher(LocomotionState,'/robot/locomotion_state',q)
        self.create_timer(0.1,self.cb)
    def cb(self):
        m=LocomotionState(); m.stamp=self.get_clock().now().to_msg(); m.epoch=1
        m.mode=0; m.state=1; m.actuation_ready=True; m.perception_pose_valid=True; m.reason='replay'
        self.pub.publish(m)
rclpy.init(); rclpy.spin(P())
