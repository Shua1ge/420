import rclpy, math
from rclpy.node import Node
from tf2_ros import StaticTransformBroadcaster
from geometry_msgs.msg import TransformStamped
rclpy.init(); n=Node('lidar_static_tf')
b=StaticTransformBroadcaster(n)
t=TransformStamped()
t.header.stamp=n.get_clock().now().to_msg()
t.header.frame_id='go2/base_footprint'
t.child_frame_id='go2/base/exploration_lidar'
t.transform.translation.x=0.187; t.transform.translation.y=0.0; t.transform.translation.z=0.0803
p=0.22689280275926285
t.transform.rotation.x=0.0; t.transform.rotation.y=math.sin(p/2); t.transform.rotation.z=0.0; t.transform.rotation.w=math.cos(p/2)
b.sendTransform(t)
n.get_logger().info('lidar static tf published')
rclpy.spin(n)
